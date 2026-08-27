class_name Missile
extends Node3D
## Kinematic store: ejects from the bay, lights the motor, then flies
## proportional navigation until the fuse or its lifetime runs out.

const N_GAIN := 3.6

var wid := "aim9"
var ws := {}
var vel := Vector3.ZERO
var shooter: Node = null
var target: Node3D = null
var team := 0
var armed := false
var age := 0.0
var motor := 0.0
var dead := false
var _start_xf := Transform3D.IDENTITY
var _eject := 0.0
var _trail: GPUParticles3D
var _flame: MeshInstance3D
var _seek_lost := 0.0
var _mask_check := 0.0
var _masked := false
var _clutter_t := 0.0
var _min_d := 1e9        # closest the round ever got to the aircraft it was aimed at
var _min_age := 0.0

func launch(id: String, xf: Transform3D, carrier_vel: Vector3, from: Node, tgt: Node3D) -> void:
	wid = id
	ws = WeaponSpec.get_spec(id)
	_start_xf = xf
	vel = carrier_vel
	shooter = from
	target = tgt
	# `in` on a null shooter raises, and the raise aborts the rest of launch()
	team = (from.team if "team" in from else 0) if is_instance_valid(from) else 0
	_eject = ws["eject"]

func _ready() -> void:
	top_level = true
	global_transform = _start_xf
	var mi := MeshKit.mi(WeaponSpec.build_mesh(wid), "Body")
	add_child(mi)
	# The smoke follows the round's own girth rather than being one width for
	# everything. A naval round is a foot and a half across and four and three
	# quarter metres long — it should not leave the same thread behind it as a
	# Sidewinder.
	var bore: float = float(ws["dia"])
	_trail = Effects.trail_particles(ws["trail"],
		clampf(1.4 + bore * 9.0, 1.4, 5.5), int(clampf(64.0 + bore * 220.0, 64.0, 150.0)))
	_trail.emitting = false
	add_child(_trail)
	if ws["burn"] > 0.0:
		var st := MeshKit.begin()
		# a bigger motor makes a bigger flame
		MeshKit.cone(st, bore * 0.45, 0.02, 0.0, 2.6 + bore * 3.0, Vector3.ZERO,
			8, false)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.albedo_color = Color(1.0, 0.85, 0.55, 0.75)
		_flame = MeshKit.mi(MeshKit.finish(st, fm), "Flame")
		_flame.position = Vector3(0, 0, ws["length"] * 0.5)
		_flame.visible = false
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_flame)
	if target and target.has_method("warn_missile") and ws["kind"] != "bomb":
		target.warn_missile()
	reset_physics_interpolation()
	Effects.dust(get_tree().current_scene, global_position, 1.4)

func _physics_process(delta: float) -> void:
	if dead:
		return
	age += delta
	if age > ws["life"]:
		_die(false)
		return
	# --- separation: fall clear of the bay before the motor lights ---------
	var boosting := false
	if age < 0.28:
		vel += Vector3.DOWN * (9.81 + _eject) * delta
	else:
		if not _trail.emitting:
			_trail.emitting = true
			if _flame:
				_flame.visible = ws["burn"] > 0.0
		armed = age > ws["arm_time"]
		boosting = age - 0.28 < ws["burn"]
		var dir := -global_transform.basis.z
		if boosting:
			vel += dir * ws["boost"] * delta
			motor = 1.0
		else:
			motor = 0.0
			if _flame:
				_flame.visible = false
		var sp := vel.length()
		var rho: float = 1.225 * exp(-maxf(global_position.y, 0.0) / 8500.0)
		vel -= vel.normalized() * ws["drag"] * rho / 1.225 * sp * sp * delta
		vel += Vector3.DOWN * 9.81 * delta
		_guide(delta)

	var from := global_position
	var to := from + vel * delta
	global_position = to
	if vel.length_squared() > 4.0:
		var fwd := vel.normalized()
		var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3.FORWARD
		global_transform.basis = Basis.looking_at(fwd, up)

	# --- terminal checks --------------------------------------------------
	# The sea is a surface, not a window. Testing only against the height field
	# let a weapon aimed at a ship swim down to the seabed a couple of hundred
	# metres below and go off there, harming nothing on the way past.
	var sea_bed := Sim.height_at(to.x, to.z)
	if to.y < Sim.WATER_LEVEL and sea_bed < Sim.WATER_LEVEL:
		var hit := Vector3(to.x, Sim.WATER_LEVEL, to.z)
		# Up onto the surface before it goes off. `_die` draws the fireball at
		# the round's own position, and by the time this test trips the round is
		# already under the sea — so a bomb into the water made a splash with
		# the explosion hidden beneath it, and read as a dud.
		# clear of the surface, not level with it: what you see of a warhead
		# going off in the water is the column standing above it
		global_position = hit + Vector3(0, maxf(float(ws["fuse"]) * 0.4, 4.0), 0)
		Effects.splash(get_tree().current_scene, hit, maxf(float(ws["fuse"]) * 0.9, 6.0))
		_ground_burst(hit)
		_die(true)
		return
	if to.y < sea_bed:
		# A missile that goes into the ground still has a warhead on it. It used
		# to make a flash and do nothing, so a Sidewinder could be walked into a
		# building without marking it.
		var gnd := Vector3(to.x, Sim.height_at(to.x, to.z), to.z)
		global_position = gnd + Vector3(0, 1.2, 0)   # same reason as above
		_ground_burst(gnd)
		_die(true)
		return
	# a round that has stopped flying has arrived at something: go off rather
	# than hang in the air next to the target
	if armed and vel.length() < 40.0 and age > 1.5:
		_die(true)
		return
	if Sim.debug_weapons and ws["kind"] == "bomb" and fmod(age, 1.0) < delta:
		var td := -1.0
		if target and is_instance_valid(target):
			td = global_position.distance_to(target.global_position)
		print("[bomb] age=%.1f armed=%s spd=%.0f  to target=%.1f  tgt=%s" % [
			age, str(armed), vel.length(), td,
			str(target.name) if target and is_instance_valid(target) else "none"])
	if armed:
		# sweep the travelled segment: at 1 km/s closing speed a point test would
		# step straight past a 9 m fuse radius
		var best: Node = null
		var best_gap := 1e9
		var best_d := 1e9
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == shooter:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			if ("team" in n) and n.team == team and n != target:
				continue
			var np: Vector3 = n.global_position
			var d := Geometry3D.get_closest_point_to_segment(np, from, to).distance_to(np)
			# Against the target's *surface*, not its origin. A destroyer is a
			# hundred and fifty five metres long with its origin amidships, so a
			# Sidewinder arriving at the bow was seventy metres from the point
			# this used to measure — far outside any fuse radius. It flew
			# through the ship and went off in the sea beyond, and the same
			# arithmetic quietly under-fused every large target in the game.
			var r: float = n.hit_radius() if n.has_method("hit_radius") else 0.0
			var gap: float = d - r
			if gap < best_gap:
				best_gap = gap
				best_d = d
				best = n
		if best and best_gap < float(ws["fuse"]):
			_hit(best, best_d)

## Where a bomb goes on aiming at once whatever it was following has gone. A
## laser spot is a *place*: the second and third rounds of a salvo were losing
## guidance the moment the first one killed the thing they were all aimed at,
## and finishing wherever they happened to be pointed — measured, 145 m out
## while the leader landed at 19 m. That reads exactly like a bomb stopping
## early or wandering off into its neighbours.
var _last_aim := Vector3.INF

func _guide(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_coast_to_mark(delta)
		return
	if target.has_method("is_alive") and not target.is_alive():
		if Sim.debug_weapons:
			print("[msl] %s dropped %s at age %.1f: target reported dead" % [
				wid, str(target.name), age])
		_last_aim = target.global_position
		target = null
		_coast_to_mark(delta)
		return
	var tpos: Vector3 = target.global_position
	_last_aim = tpos
	var tvel: Vector3 = Vector3.ZERO
	if target.has_method("get_velocity"):
		tvel = target.get_velocity()
	elif "linear_velocity" in target:
		tvel = target.linear_velocity

	# IR seekers can be spoofed by flares
	if ws["flare_bait"] > 0.0 and target.has_method("flare_active") and target.flare_active():
		if randf() < ws["flare_bait"] * delta * 2.0:
			target = null
			return
	# and radar seekers by chaff, which until now nothing carried: a radar round
	# had no counter at all, so a SAM site that got a shot off was unbeatable
	# except by outrunning it.
	# Ground clutter. A radar seeker looking down at a target close to the
	# ground is trying to pick it out of the return from every field, hedge and
	# roof behind it, and the slower the closing rate the harder that is. This
	# is why anyone being shot at by a radar missile goes low, and until now it
	# bought nothing at all: the seeker tracked a target at fifty feet exactly
	# as well as one at forty thousand.
	if String(ws["kind"]) == "radar":
		var tgt_agl: float = tpos.y - Sim.height_at(tpos.x, tpos.z)
		var look_down: float = clampf((global_position.y - tpos.y) / 900.0, 0.0, 1.0)
		var low: float = 1.0 - smoothstep(120.0, 1400.0, tgt_agl)
		var clutter: float = low * look_down
		if clutter > 0.01:
			_clutter_t += delta * clutter
			# a couple of seconds in the notch and the track is gone
			if _clutter_t > 2.4:
				if Sim.debug_weapons:
					print("[msl] %s lost %s in ground clutter at age %.1f: target %.0f m agl, %.0f m below the round" % [
						wid, str(target.name), age, tgt_agl,
						global_position.y - tpos.y])
				target = null
				return
		else:
			_clutter_t = maxf(_clutter_t - delta * 1.5, 0.0)
	var cb: float = float(ws.get("chaff_bait", 0.0))
	if cb > 0.0 and target.has_method("chaff_active") and target.chaff_active():
		if randf() < cb * delta * 2.0:
			if Sim.debug_weapons:
				print("[msl] %s decoyed by chaff at age %.1f" % [wid, age])
			target = null
			return
	var los := tpos - global_position
	var dist := los.length()
	if dist < _min_d:
		_min_d = dist
		_min_age = age
	if dist < 0.5:
		return
	# And the seeker has to be able to see it. Ducking behind a ridge with a
	# round already in the air is a real defence and it did nothing: the missile
	# tracked straight through the hill. Checked a few times a second rather
	# than every frame — it is a ray march, and there can be a lot of rounds up.
	_mask_check -= delta
	if _mask_check <= 0.0:
		_mask_check = 0.25
		_masked = not Sim.line_of_sight(global_position, tpos)
	if _masked:
		_seek_lost += delta
		if _seek_lost > 0.6:
			if Sim.debug_weapons:
				print("[msl] %s dropped %s at age %.1f: terrain masked at %.0f m" % [
					wid, str(target.name), age, dist])
			target = null
		return
	var seeker_ang := rad_to_deg((-global_transform.basis.z).angle_to(los))
	if seeker_ang > ws["seeker_fov"]:
		_seek_lost += delta
		if _seek_lost > 1.2:
			if Sim.debug_weapons:
				print("[msl] %s dropped %s at age %.1f: seeker off by %.0f deg (fov %.0f), range %.0f m" % [
					wid, str(target.name), age, seeker_ang, float(ws["seeker_fov"]), dist])
			target = null
		return
	_seek_lost = 0.0
	if Sim.debug_weapons and fmod(age, 1.0) < delta:
		print("[gd] %s age=%.1f d=%.0f spd=%.0f tspd=%.0f seek=%.0f los=%s" % [
			wid, age, dist, vel.length(), tvel.length(), seeker_ang,
			str((los / dist).snapped(Vector3.ONE * 0.01))])
	var rel := tvel - vel
	# lead using proportional navigation, with a lofted midcourse for bombs
	var omega := los.cross(rel) / maxf(los.length_squared(), 1.0)
	var closing := -rel.dot(los / dist)
	var accel := omega.cross(vel) * N_GAIN
	if ws["kind"] == "bomb":
		# A guided bomb points at the target and lets gravity do the rest. It
		# steers the *direction* of its velocity onto the line of sight and
		# leaves the magnitude alone, so it noses over and accelerates down the
		# slope the way a falling thing does.
		#
		# Holding gravity off with the same authority — which is what this did —
		# makes it glide flat instead, and with a bomb's drag coefficient it
		# then bleeds out: released from seven kilometres it arrived at the
		# target's neighbourhood doing 59 m/s and expired at the end of its
		# seventy second life, still two hundred metres short.
		var v_dir := vel.normalized() if vel.length() > 1.0 else -global_transform.basis.z
		var want_dir := (tpos - global_position).normalized()
		accel = (want_dir - v_dir) * maxf(vel.length(), 90.0) * 2.6
	elif closing < -50.0:
		accel *= 0.2
	# A round that has slowed down cannot pull its rated g, which is what makes a
	# late defensive break survivable. The reference speed is per weapon: a bomb
	# never flies at missile speeds, and scaling it against one left the JDAM
	# unable to hold its own weight, let alone steer.
	#
	# It has to be the speed the round pulls its rated g *at*, which is near its
	# peak — not its launch speed. Set to the latter, an AMRAAM peaking at 1105
	# m/s had this term pinned at 1.0 for the whole engagement and pulled the
	# full thirty-five g right down to the merge, so breaking hard bought
	# nothing at all.
	var energy := clampf(vel.length() / float(ws.get("ref_speed", 420.0)), 0.15, 1.0)
	# And the air it is turning against. A fin makes its lift from dynamic
	# pressure, which is density times speed squared, so the same round is far
	# less agile at forty thousand feet than it is down low — and a shot that
	# has to climb to reach you arrives slower as well as thinner. Sea level is
	# the reference, so nothing changes for a missile fired on the deck.
	var rho_g: float = exp(-clampf(global_position.y, 0.0, 30000.0) / 8500.0)
	var g_max: float = ws["max_g"] * 9.81 * energy * energy \
		* clampf(rho_g, 0.22, 1.0)
	if Sim.debug_weapons and String(ws["kind"]) == "radar" and fmod(age, 0.5) < delta:
		print("[g] %s age=%.1f spd=%.0f alt=%.0f  wants %.1f g, has %.1f g%s" % [
			wid, age, vel.length(), global_position.y, accel.length() / 9.81,
			g_max / 9.81, "  <- LIMITED" if accel.length() > g_max else ""])
	if accel.length() > g_max:
		accel = accel.normalized() * g_max
	vel += accel * delta
	# Induced drag: a turn is not free.
	#
	# This is what was missing. Available g was never the limit — instrumented
	# through a whole engagement the round wanted 0.1 to 4.4 g while holding
	# 17.4, so the clamp never once engaged and changing it changed nothing.
	# What it could do was turn as hard as it liked at no cost, so a defensive
	# break bled the aeroplane's energy and none of the missile's. A fin that
	# makes side force makes drag with it, as the square of the force and
	# inversely with the air it has to work in, and that is precisely why a late
	# hard break works: the round follows you and arrives with nothing left.
	# Not for bombs. A bomb's steering term carries `+ UP * 9.81` to hold gravity
	# off, and that is almost entirely lateral to a flat trajectory — so it read
	# as a permanent hard turn and charged drag for it. Worse, the charge grows
	# as the inverse square of speed, so the slower it got the harder it braked:
	# a JDAM released from seven kilometres decelerated to 40 m/s two thousand
	# metres up, tripped the "stopped flying" self-destruct and went off five
	# kilometres short. A bomb's lift-induced drag is already in its own drag
	# coefficient, which is an order of magnitude above a missile's.
	var lat := (accel - accel.project(vel.normalized())).length() \
		if String(ws["kind"]) != "bomb" else 0.0
	if lat > 1.0:
		var q: float = maxf(rho_g * vel.length_squared(), 1.0)
		var bleed: float = float(ws.get("induced", 0.9)) * lat * lat / q * 1000.0
		# and never more than a quarter of what it has left in a second, so a
		# slow round cannot brake itself to a standstill
		vel -= vel.normalized() * minf(bleed, vel.length() * 0.25) * delta

## Keep flying the last place the target was, for a weapon that is aimed at
## the ground rather than at a thing. A missile has nothing to coast to.
func _coast_to_mark(_delta: float) -> void:
	if String(ws["kind"]) != "bomb" or _last_aim == Vector3.INF:
		return
	var v_dir := vel.normalized() if vel.length() > 1.0 else -global_transform.basis.z
	var want_dir := (_last_aim - global_position).normalized()
	var accel := (want_dir - v_dir) * maxf(vel.length(), 90.0) * 2.6
	var g_max: float = ws["max_g"] * 9.81
	if accel.length() > g_max:
		accel = accel.normalized() * g_max
	vel += accel * _delta

func _hit(what: Node, miss := 0.0) -> void:
	# a detonation out at the edge of the fuse envelope only peppers the target
	var falloff: float = clampf(1.0 - miss / maxf(ws["fuse"], 0.1), 0.22, 1.0)
	if what.has_method("take_hit"):
		what.take_hit(ws["damage"] * falloff, _from_who())
	if shooter and shooter.has_method("on_weapon_hit"):
		shooter.on_weapon_hit(what, wid)
	_die(true)

## Warhead going off against the ground or a structure: everything inside the
## blast takes it, and the scenery in the middle comes down.
func _ground_burst(at: Vector3) -> void:
	if ws["kind"] == "bomb":
		return                     # the bomb path does its own, much bigger, one
	var r: float = maxf(float(ws["fuse"]) * 1.8, 12.0)
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == shooter or not n.has_method("take_hit"):
			continue
		var d: float = n.global_position.distance_to(at)
		if d < r:
			n.take_hit(float(ws["damage"]) * clampf(1.0 - d / r, 0.2, 1.0), _from_who())
	var scn = get_tree().current_scene.get("scenery")
	if scn != null and is_instance_valid(scn) and scn.has_method("damage_area"):
		var flat: int = scn.damage_area(at, r * 0.8)
		if Sim.debug_weapons:
			var near := 0
			if scn.has_method("count_standing"):
				near = scn.count_standing(at, 120.0)
			print("[msl] %s ground burst at %s: radius %.0f m, flattened %d, %d standing within 120 m" % [
				wid, str(at.round()), r * 0.8, flat, near])

## Who to credit for the hit. A round often outlives whoever fired it, and
## handing a freed object to a typed Node parameter does not merely pass null:
## it raises, and the raise aborts the rest of the damage loop. A bomb whose
## shooter had died therefore did no damage at all -- it detonated on the
## target, and the target stood there at full health.
func _from_who() -> Node:
	return shooter if is_instance_valid(shooter) else null

func _die(big: bool) -> void:
	if dead:
		return
	dead = true
	Effects.explosion(get_tree().current_scene, global_position, 9.0 if big else 4.0)
	if ws["kind"] != "bomb" and Sim.debug_weapons:
		var near := 9999.0
		var nn := "-"
		for n in get_tree().get_nodes_in_group("hittable"):
			if is_instance_valid(n) and n != shooter:
				var dd2: float = n.global_position.distance_to(global_position)
				if dd2 < near:
					near = dd2
					nn = str(n.name)
		print("[msl] %s died at age %.1f, %.0f m/s, closest %s at %.1f m (fuse %.1f), best pass %.1f m at age %.1f" % [
			wid, age, vel.length(), nn, near, float(ws["fuse"]), _min_d, _min_age])
	if ws["kind"] == "bomb" and Sim.salvo_watch:
		var gh: float = Sim.height_at(global_position.x, global_position.z)
		Sim.salvo_log.append("%s died at %.1fs, %.0f m from the mark, at %s — %.0f m above the ground there, %.0f m/s" % [
			wid, age, global_position.distance_to(Sim.salvo_mark)
			if Sim.salvo_mark != Vector3.INF else -1.0,
			str(global_position.round()), global_position.y - gh, vel.length()])
	if ws["kind"] == "bomb" and Sim.debug_weapons:
		var nearest := 9999.0
		var nm := "-"
		for n in get_tree().get_nodes_in_group("ground_targets"):
			if is_instance_valid(n):
				var dd: float = n.global_position.distance_to(global_position)
				if dd < nearest:
					nearest = dd
					nm = str(n.name)
		print("[bomb] detonated at %s, nearest ground target %s at %.1f m" % [
			str(global_position.round()), nm, nearest])
	if ws["kind"] == "bomb" or bool(ws.get("nuclear", false)):
		# A big warhead does not need a direct hit: lethal radius with a linear
		# falloff, whether it went off on the target or in the dirt. Keyed on
		# the warhead rather than on the weapon being a free-fall bomb, because
		# a submarine launched round is a rocket and still goes off like this.
		var lethal: float = float(ws.get("lethal", 38.0))
		var nuke: bool = bool(ws.get("nuclear", false))
		var hit := 0
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or not n.has_method("take_hit"):
				continue
			var d: float = n.global_position.distance_to(global_position)
			if d < lethal:
				n.take_hit(float(ws["damage"]) * clampf(1.0 - d / lethal, 0.15, 1.0), _from_who())
				hit += 1
				if Sim.debug_weapons and not nuke:
					print("[bomb]   damaged %s at %.1f m, hp now %s" % [
						str(n.name), d, str(n.get("health"))])
		if nuke:
			# flatten the scenery inside the radius as well as anything that
			# can be shot: a weapon this size does not leave the town standing
			var flattened := 0
			var scn = get_tree().current_scene.get("scenery")
			if scn != null and is_instance_valid(scn) and scn.has_method("damage_area"):
				flattened = scn.damage_area(global_position, lethal * 0.55)
			Effects.nuke(get_tree().current_scene, global_position, lethal)
			if Sim.debug_weapons:
				print("[nuke] %s detonated at %s: lethal radius %.0f m, %d units hit, %d structures flattened" % [
					wid, str(global_position.round()), lethal, hit, flattened])
		else:
			Effects.explosion(get_tree().current_scene, global_position, 30.0)
	queue_free()

func get_velocity() -> Vector3:
	return vel

func _enter_tree() -> void:
	add_to_group("missiles")
