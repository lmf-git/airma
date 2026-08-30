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
## Folding tail fins: how far in they sit in the tube, and how long after
## leaving it they take to lock out.
const FIN_STOWED := 0.06
const FIN_OUT_AT := 0.30
const FIN_OUT_OVER := 0.45
var _fins: MeshInstance3D = null
## Fired out of a canister rather than off an aeroplane: straight up, then over.
##
## And under its own booster. The `boost` in the weapon table is the sustainer
## of a round that is *dropped* from an aeroplane already doing three hundred
## knots -- 42 m/s^2 of it, which is ample when you start at speed and useless
## when you start at rest pointing at the sky. Launched from a standstill the
## round was still doing 34 m/s two seconds later, and the "it has stopped
## flying, it must have hit something" check put it in the ground. A canister
## round carries a launch booster; this is it.
const VLS_OVER := 4.0
const VLS_PITCH := 0.66          # about 38 degrees, the arc it settles onto
const VLS_BOOST := 140.0
const VLS_BOOST_FOR := 2.4
var _vls := false
## Which way this particular round's timing error throws it, fixed when it
## leaves the rail.
var _aim_bias := Vector3.ZERO
## The angle this round was thrown at.
var _pitch := VLS_PITCH
## How much further than the target the airless arc has to reach before the
## motor is cut, to pay for the air it actually flies through.
## Most of a ballistic arc is thin air, so the airless range formula is not far
## wrong for it -- unlike a round that spends its whole flight low down, which
## is what the larger figure this was briefly set to was tuned for.
const BALLISTIC_DRAG_ALLOW := 1.35
## Motor cut, and it does not come back.
var _burnt := false
var motor := 0.0
var dead := false
var _start_xf := Transform3D.IDENTITY
var _eject := 0.0
var _trail: GPUParticles3D
var _flame: MeshInstance3D
var _glow: OmniLight3D
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
	_aim_bias = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)).normalized()
	# The angle to throw it at, worked out from how far it has to go.
	#
	# A ballistic weapon is aimed by its launch angle, and there are two angles
	# that reach any given range: a flat one and a steep one. Fired at a target
	# far inside its reach -- which a two thousand kilometre missile always is,
	# on a map twelve hundred across -- the flat solution is nearly horizontal
	# and useless, and the steep one is nearly vertical, which is exactly what
	# an over-ranged ballistic missile does. Fixed at 38 degrees it simply flew
	# past everything.
	_pitch = VLS_PITCH
	if String(ws.get("kind", "")) == "cruise" and is_instance_valid(tgt):
		# A cruise round climbs to its cruising height and levels off; it does
		# not get thrown up at thirty-eight degrees. Pitched over like a
		# ballistic shot, a 26 g sustainer pushing along that nose out-climbs
		# anything the guidance can pull back at Mach 7 -- it went through a six
		# kilometre cruise height, reached twenty, and never recovered.
		var run: float = maxf(Vector2(tgt.global_position.x - xf.origin.x,
			tgt.global_position.z - xf.origin.z).length(), 1000.0)
		# Over more than half the run, not a quarter of it. A round at Mach 7
		# with fifteen g turns about four degrees a second, so a nineteen degree
		# climb takes six seconds to level out of and gains three and a half
		# kilometres doing it -- it sailed through a six kilometre cruise height
		# and levelled at fifteen. A shallower climb has less to undo.
		# The cruising height a shot this long is worth. A weapon's entry gives
		# the height it cruises at when it has the range to use one, and for a
		# Zircon that is six kilometres -- which is right over sixty and absurd
		# over twenty-five. At twenty-five it reached 6.3 km still climbing,
		# arrived over the ship at 7.3 km with the dive not yet started, and
		# came down twenty-seven kilometres the other side of it. The climb has
		# to be worth the descent that pays for it: a round cannot spend more
		# height than it can shed in the distance it has left.
		# How tightly this round can turn at all. A Zircon holds Mach 8 and is
		# rated at fifteen g, and v squared over a is a turn radius of fifty
		# kilometres -- so it cannot dive, level and strike inside a box a
		# fraction of that across. Every number below comes out of it.
		var v: float = maxf(float(ws.get("ref_speed", 300.0)), 60.0)
		_turn_r = v * v / maxf(float(ws.get("max_g", 10.0)) * 9.81, 1.0)
		# The height a descent can shed over a given ground distance, when it
		# has to rotate into the dive and out of it again at that radius: about
		# D squared over four R. Inverted, this is the cruising height the run
		# can pay for -- roughly half of it is spent climbing, the rest coming
		# down. Six kilometres needs thirty-four to get rid of; asked to do it
		# in sixteen, the round arrived over the ship still five kilometres up
		# and scored a proximity hit instead of striking it.
		var descent: float = run * 0.55
		_deck = minf(float(ws.get("cruise_alt", 60.0)),
			descent * descent / (4.0 * _turn_r))
		_pitch = clampf(atan(_deck / (run * 0.55)),
			deg_to_rad(4.0), deg_to_rad(30.0))
	elif bool(ws.get("loft", false)) and is_instance_valid(tgt):
		var far_flat: float = Vector2(tgt.global_position.x - xf.origin.x,
			tgt.global_position.z - xf.origin.z).length()
		var vbo: float = maxf(float(ws.get("ref_speed", 1000.0)) * 0.85, 100.0)
		var s2: float = clampf(far_flat * 9.81 * BALLISTIC_DRAG_ALLOW
			/ (vbo * vbo), 0.0, 1.0)
		# The steep solution. Two angles reach any given range, and a ballistic
		# missile flies the high one -- that is what makes it ballistic. The
		# weapons that want the flat, fast, depressed profile are the hypersonic
		# anti-ship rounds, and those are cruise missiles: they hold a speed and
		# follow the ground, and they never come through here.
		_pitch = clampf((PI - asin(s2)) * 0.5, deg_to_rad(34.0), deg_to_rad(60.0))

## The cruising height this particular shot chose, which depends on how far it
## has to go. Zero until a cruise round with a target works it out at launch.
var _deck := 0.0
## Its turn radius at cruising speed, which is what decides both that height and
## how early the descent has to begin.
var _turn_r := 0.0

## How high to hold over the highest ground ahead on the run in. This is a
## clearance, so it is measured in tens of metres -- it was a fraction of the
## cruise height, which for a sea skimmer cruising at twenty-four metres came
## to eight and was fine, and for a hypersonic round cruising at kilometres
## came to two thousand: a floor two kilometres up, held until nine hundred
## metres from the target, which at Mach 8 is a third of a second to lose it in.
## Not hitting the ridge and choosing a cruising height are different jobs.
func _crest(deck: float) -> float:
	return minf(deck * 0.35, 150.0)

func _ready() -> void:
	top_level = true
	global_transform = _start_xf
	# A round that comes out of a canister is stowed with its fins folded flat
	# against the body -- they have to be, the tube is barely wider than the
	# round -- and they snap out once it is clear of the launcher. Built with
	# them already deployed, a Kalibr stood in its tube with its tail sticking
	# through the walls of it.
	var folds: bool = bool(ws.get("folding", false))
	_vls = folds
	var mi := MeshKit.mi(WeaponSpec.build_mesh(wid, not folds), "Body")
	add_child(mi)
	if folds:
		_fins = MeshKit.mi(WeaponSpec.build_fins(wid), "Fins")
		_fins.scale = Vector3(FIN_STOWED, FIN_STOWED, 1.0)
		add_child(_fins)
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
		# A motor is a light. The cone was drawn additively and lit nothing at
		# all, so at night a round in boost was a faint smear against a black
		# sky instead of the brightest thing for a mile.
		_glow = OmniLight3D.new()
		_glow.light_color = Color(1.0, 0.72, 0.42)
		_glow.light_energy = 0.0
		_glow.omni_range = 30.0 + bore * 120.0
		_glow.omni_attenuation = 1.4
		_glow.shadow_enabled = false
		_glow.position = Vector3(0, 0, ws["length"] * 0.5 + 1.0)
		add_child(_glow)
	if target and target.has_method("warn_missile") and ws["kind"] != "bomb":
		target.warn_missile()
	reset_physics_interpolation()
	Effects.dust(get_tree().current_scene, global_position, 1.4)

func _physics_process(delta: float) -> void:
	if dead:
		return
	age += delta
	# Vertical launch, then over onto the bearing during the boost.
	#
	# A canister round leaves the tube pointing at the sky, and the ordinary
	# guidance -- which trims a heading it is already roughly on -- cannot bring
	# a round round through ninety degrees. Measured: launched at a mark 27.4 km
	# away, the closest it came in thirty seconds was 26.9 km. It went straight
	# up and stayed there. This is the pitch-over a vertical launch actually
	# does, and once it is on the bearing the normal guidance has something it
	# can work with.
	if _vls and age > 0.30 and age < 0.30 + VLS_OVER and is_instance_valid(target):
		var flat: Vector3 = target.global_position - global_position
		flat.y = 0.0
		if flat.length_squared() > 1.0:
			var t: float = clampf((age - 0.30) / VLS_OVER, 0.0, 1.0)
			var lofted: Vector3 = (flat.normalized() * cos(_pitch)
				+ Vector3.UP * sin(_pitch)).normalized()
			var want: Vector3 = Vector3.UP.slerp(lofted, t * t * (3.0 - 2.0 * t))
			var sp: float = maxf(vel.length(), 1.0)
			vel = vel.lerp(want * sp, clampf(delta * 2.6, 0.0, 1.0))
	if _fins != null:
		var fo: float = clampf((age - FIN_OUT_AT) / FIN_OUT_OVER, 0.0, 1.0)
		var k: float = lerpf(FIN_STOWED, 1.0, fo * fo * (3.0 - 2.0 * fo))
		_fins.scale = Vector3(k, k, 1.0)
	if age > ws["life"]:
		_die(false)
		return
	# --- separation: fall clear of the bay before the motor lights ---------
	var boosting := false
	if age < 0.28:
		# A round leaving a wing pylon is dropped clear before the motor lights.
		# One leaving a canister is thrown *up* out of it, and pushing it down
		# for the first quarter second undid most of the launch.
		vel += (Vector3.UP * _eject - Vector3.DOWN * 9.81) * delta if _vls \
			else Vector3.DOWN * (9.81 + _eject) * delta
	else:
		if not _trail.emitting:
			_trail.emitting = true
			if _flame:
				_flame.visible = ws["burn"] > 0.0
		armed = age > ws["arm_time"]
		boosting = age - 0.28 < ws["burn"] and not _burnt
		# Burnout, for anything that flies an arc.
		#
		# A ballistic weapon is aimed by *when it stops burning*, not by steering
		# all the way in. Left under power it simply kept accelerating along its
		# launch vector -- Mach 16 and forty kilometres up, having gone straight
		# over the target -- and at that speed with seven g of authority its turn
		# radius is four hundred and sixty kilometres, so nothing could bring it
		# back down. It cuts the motor the moment the arc it is already on
		# reaches the target, and falls on it.
		if boosting and bool(ws.get("loft", false)) and is_instance_valid(target):
			var tp: Vector3 = target.global_position
			var flat: float = Vector2(tp.x - global_position.x,
				tp.z - global_position.z).length()
			var vnow: float = vel.length()
			if vnow > 50.0:
				var sn: float = clampf(vel.y / vnow, -1.0, 1.0)
				var cs: float = sqrt(maxf(1.0 - sn * sn, 0.0))
				# v^2 sin(2a) / g, the range of the arc it is on right now --
				# in a vacuum. This round flies through air, and the difference
				# is not small: cutting the motor the moment the airless arc
				# reached the target put a Zircon into the ground thirty-four
				# kilometres short. The allowance is what the drag costs it.
				var reach: float = vnow * vnow * maxf(2.0 * sn * cs, 0.02) / 9.81
				if sn > 0.05 and reach >= flat * BALLISTIC_DRAG_ALLOW:
					# and it stays out. `boosting` is worked out afresh every
					# frame from the age against the burn time, so cutting it
					# locally lasted exactly one frame: the motor relit and the
					# round accelerated away from a target it had already closed
					# to three kilometres, ending up sixty out and still going.
					_burnt = true
					boosting = false
					motor = 0.0
					if _flame:
						_flame.visible = false
		# A cruise missile throttles. Ours ran its sustainer flat out for the
		# whole flight, so it had thrust to spare at every moment and climbed
		# two and a half times its own cruising height before the guidance could
		# argue it down. Holding the design speed is what the motor is for.
		# ...up to the design speed, and then faster for the run in.
		#
		# A 3M-54 cruises subsonic and sprints at the end -- the last stretch is
		# flown at close to Mach three, which is the whole point of the weapon:
		# it is slow where nothing can see it and fast where something might
		# shoot at it. Held to the cruise figure for the whole flight it took
		# four minutes to cross sixty kilometres and arrived at the speed it set
		# out at.
		var hold: float = float(ws.get("ref_speed", 1.0e9))
		var sprint: float = float(ws.get("sprint_speed", 0.0))
		if sprint > hold and is_instance_valid(target):
			var run_left: float = global_position.distance_to(
				target.global_position)
			if run_left < float(ws.get("sprint_at", 0.0)):
				hold = sprint
		if boosting and String(ws.get("kind", "")) == "cruise" \
				and vel.length() > hold:
			boosting = false
			motor = 0.0
		var dir := -global_transform.basis.z
		if _vls and age < VLS_BOOST_FOR:
			vel += dir * VLS_BOOST * delta
		if boosting:
			vel += dir * ws["boost"] * delta
			motor = 1.0
			if _glow:
				# guttering a little, the way a solid motor does
				_glow.light_energy = 5.5 + sin(age * 47.0) * 0.8
		else:
			motor = 0.0
			if _flame:
				_flame.visible = false
			if _glow and _glow.light_energy > 0.0:
				# it does not switch off: the nozzle stays hot for a moment
				_glow.light_energy = maxf(_glow.light_energy - delta * 9.0, 0.0)
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
	# Some rounds do not arrive as one thing. A bus carrying re-entry vehicles,
	# or a cluster bomb carrying bomblets, opens at a set height and lets its
	# load finish the job.
	if armed and not _split and ws.has("mirv"):
		var bed: float = maxf(Sim.height_at(global_position.x, global_position.z),
			Sim.WATER_LEVEL)
		# On the way down, not on the way up. The test was height above the
		# ground alone, which is satisfied the moment the round leaves the
		# ground -- so a bus lofted from a launcher opened at three kilometres
		# while still climbing, and scattered its load over its own launch site.
		# ...and over the target, not merely low enough. Height alone opened the
		# bus at twelve kilometres with eighteen still to run: the load is
		# unpowered once it is off, so it carried its share of the bus's speed
		# for as long as it took to fall and came down two and a half
		# kilometres short. What decides the release is whether the bus is on
		# the target *ballistically* -- how far the load will travel before it
		# is down, against how far there is left to go.
		var open_now: bool = vel.y < 0.0 \
			and global_position.y - bed < float(ws.get("mirv_at", 1000.0))
		if open_now and is_instance_valid(target):
			var drop: float = maxf(global_position.y - bed, 1.0)
			var vy: float = absf(vel.y)
			# h = vy t + g t squared over two, solved for t
			var tfall: float = (vy + sqrt(vy * vy + 2.0 * 9.81 * drop)) / 9.81
			var reach: float = Vector2(vel.x, vel.z).length() * tfall
			var plan: float = Vector2(
				target.global_position.x - global_position.x,
				target.global_position.z - global_position.z).length()
			# still long of it: hold, and let both numbers come down together
			if plan > reach * 1.05:
				open_now = false
			# ...but never all the way to the ground. A bus that is going to
			# land short is long of its target for the whole descent, so this
			# test alone held the load in right down to the deck and the round
			# arrived as one unopened bus carrying nothing that could go off.
			# Below a quarter of the release height it opens regardless: a
			# spread that lands short still beats no spread at all.
			if global_position.y - bed < float(ws.get("mirv_at", 1000.0)) * 0.25:
				open_now = true
		if open_now:
			_open_up()
			return
	if _fuse_check(from, to):
		return
	# A round sent to a *place* has nothing to fuse on: an aiming point is a
	# bare node, not a contact, so the proximity fuse never sees it. The
	# strategic round flew past the mark it could not quite turn onto -- best
	# pass 1.7 km -- and carried on into the sea three kilometres beyond, where
	# its four kilometre warhead did nothing to what it had been sent at. It
	# bursts at its closest approach instead, which is what an airburst is.
	if armed and is_instance_valid(target) and target.is_in_group("no_lock"):
		var dm := global_position.distance_to(target.global_position)
		if dm < _mark_best:
			_mark_best = dm
		elif _mark_best < 9000.0 and dm > _mark_best + 15.0:
			_die(true)
			return
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
	# A building is as solid as the ground it stands on. Without this a round
	# aimed at a hangar flew through it and burst on the dirt on the far side,
	# and a Maverick could be put through an office block from end to end.
	if armed or age > 0.25:
		var into := Obstacles.hit(to, 0.6)
		if into >= 0:
			global_position = to
			_ground_burst(to)
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
	# ...but not while the booster is still burning: a round that has not got up
	# to speed yet has not arrived anywhere.
	if armed and vel.length() < 40.0 and age > 1.5 \
			and not (_vls and age < VLS_BOOST_FOR + 0.6):
		_die(true)
		return
	if Sim.debug_weapons and ws["kind"] == "bomb" and fmod(age, 1.0) < delta:
		var td := -1.0
		if target and is_instance_valid(target):
			td = global_position.distance_to(target.global_position)
		print("[bomb] age=%.1f armed=%s spd=%.0f  to target=%.1f  tgt=%s" % [
			age, str(armed), vel.length(), td,
			str(target.name) if target and is_instance_valid(target) else "none"])
## Has the round arrived at what it was aimed at during this step? Answered
## before the sea and the ground are, because those checks end the round then
## and there: a Harpoon crossing the surface a few metres from a corvette was
## killed by the water and went off as a splash, and the ship took the edge of
## a ground burst instead of the warhead.
func _fuse_check(from: Vector3, to: Vector3) -> bool:
	if not armed:
		return false
	# Not bombs. A bomb is an area weapon and has its own, much bigger burst;
	# fusing it against the first thing inside eleven metres would give one
	# target a direct hit and let everything else in the blast off entirely.
	if String(ws["kind"]) == "bomb":
		return false
	# sweep the travelled segment: at 1 km/s closing speed a point test would
	# step straight past a 9 m fuse radius
	var best: Node = null
	var best_gap := 1e9
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == shooter:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if ("team" in n) and n.team == team and n != target:
			continue
		var np: Vector3 = n.global_position
		var near: Vector3 = Geometry3D.get_closest_point_to_segment(np, from, to)
		var d := near.distance_to(np)
		# Against the target's *surface*, not its origin. A destroyer is a
		# hundred and fifty five metres long with its origin amidships, so a
		# Sidewinder arriving at the bow was seventy metres from the point this
		# used to measure — far outside any fuse radius. It flew through the
		# ship and went off in the sea beyond, and the same arithmetic quietly
		# under-fused every large target in the game.
		var gap: float = d
		if n.has_method("surface_gap"):
			gap = n.surface_gap(near)
		elif n.has_method("hit_radius"):
			gap = d - n.hit_radius()
		if gap < best_gap:
			best_gap = gap
			best = n
	# ...and always the thing it was actually sent at, even when that is not a
	# radar contact. An interceptor is fired at a missile, and a missile is
	# deliberately not in the contact list.
	if is_instance_valid(target) and not target.is_in_group("hittable") \
			and target.has_method("hit_radius"):
		var tp2: Vector3 = target.global_position
		var d2 := Geometry3D.get_closest_point_to_segment(tp2, from, to).distance_to(tp2)
		var gap2: float = d2 - float(target.call("hit_radius"))
		if gap2 < best_gap:
			best_gap = gap2
			best = target
	if best == null or best_gap >= float(ws["fuse"]):
		_last_gap = 1e9
		return false
	# Hold for the closest approach. Going off the instant the target came
	# inside the envelope meant a round always detonated at the far edge of its
	# own fuse radius and never actually struck what it was aimed at. Each step
	# already measures the closest point on the length travelled, so once that
	# stops shrinking the pass is over. Not held past the surface, though --
	# there is nothing on the other side of it to wait for.
	# only held while there is somewhere left to go: the step that would put the
	# round through the surface is the last chance it gets
	var sea: float = maxf(Sim.height_at(to.x, to.z), Sim.WATER_LEVEL)
	if best == target and best_gap > 1.5 and best_gap < _last_gap - 0.05 \
			and to.y > sea:
		_last_gap = best_gap
		return false
	# the gap to the skin, which is what the fuse just measured
	_hit(best, maxf(best_gap, 0.0))
	return true

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
	# Not every entry carries one: the hypersonics and the re-entry vehicles
	# have no infrared seeker to spoof, and reading the key straight threw on
	# every guidance tick the moment one of them was in the air.
	var bait: float = float(ws.get("flare_bait", 0.0))
	if bait > 0.0 and target.has_method("flare_active") and target.flare_active():
		if randf() < bait * delta * 2.0:
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
	# Clutter is about picking an aeroplane out of the ground behind it. A round
	# aimed at something that *is* on the ground is not competing with clutter —
	# it is looking at the thing the clutter is made of — so applying this to
	# air-to-ground weapons dropped every Maverick's lock a couple of seconds
	# after launch and put it in the dirt.
	if String(ws["kind"]) == "radar" and target is Aircraft \
			and not bool(ws.get("anti_radiation", false)):
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
	# A lofted midcourse, applied before the line of sight is taken — putting it
	# after was the same as not having it at all, since proportional navigation
	# steers on `los` and never looks at the target position again.
	#
	# PN flies the shortest path to an intercept, which for a ballistic round
	# sent twenty kilometres means nosing over off the rail, throwing away the
	# loft it launched with and arriving flat — into whatever high ground is in
	# the way. Measured: into a mountain six kilometres short. Aiming high and
	# letting the aim point come down as it closes keeps the arc.
	if bool(ws.get("loft", false)):
		var flat_d := Vector2(tpos.x - global_position.x,
			tpos.z - global_position.z).length()
		# Tapered off over the last few kilometres so the round comes down onto
		# the target rather than being carried past it: aiming high all the way
		# in overshot by seven kilometres.
		var taper: float = clampf((flat_d - 3000.0) / 7000.0, 0.0, 1.0)
		tpos.y += clampf(flat_d * 0.35, 0.0, 20000.0) * taper
	# Fuse and guidance timing, expressed as a miss distance.
	#
	# A hit is a decision taken in the last few milliseconds of a closing pass.
	# Against an aeroplane closing at 250 m/s a few milliseconds is a couple of
	# metres and the round hits; against something arriving at Mach eight the
	# same few milliseconds is thirty metres and it does not. Without this an
	# SM-2 -- forty-four g and a twenty-two metre fuse -- intercepted anything
	# put in front of it, including ballistic re-entry vehicles, which made
	# every long range weapon in the game pointless.
	#
	# A fixed bias per round rather than a die roll at the end, so a miss looks
	# like one: the round goes past. Rolling for it on impact makes a weapon
	# fly through its target.
	# ...and only against something that is trying not to be hit.
	#
	# The hard case is a fuse decision on a manoeuvring air target crossing at
	# closing speed; that is what this is for, and what made interceptors far
	# too good. Applied to everything it also threw a Mach 8 anti-ship round
	# twenty-four metres wide of a stationary ship -- further than its own fuse
	# radius -- so the weapon missed by construction. A ship or a vehicle is a
	# big, slow, cooperative target and the round does not miss it on timing.
	var evasive: bool = target is Aircraft or target is Missile
	if evasive:
		var closing_now: float = (tvel - vel).length()
		tpos += _aim_bias * (float(ws.get("guide_jitter", 0.009)) * closing_now)
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
	# Only for a round homing on something that has to be *seen*. A weapon
	# flying to a coordinate does not care what is between it and the place —
	# and a lofted ballistic shot at a target twenty kilometres away has the
	# whole horizon in the way by definition. This dropped the submarine's
	# strategic round nine tenths of a second off the rail, every time, and it
	# then flew on unguided and hit nothing.
	# ...and a cruise weapon is exactly that. It runs in at thirty metres with
	# the target behind the ground it is hugging, so it is masked by definition
	# from the moment it lets down — and being masked returned out of here
	# before any guidance ran at all, which left it with no lift and nothing but
	# gravity. It went into the deck twelve kilometres short, every time, with
	# the mountain it was supposed to cross still ahead of it.
	var is_cruise: bool = String(ws["kind"]) == "cruise"
	# A ballistic round is on inertial guidance from the moment it leaves the
	# rail until it is coming down again: it flies an arc to a coordinate, and
	# it neither needs to see the target on the way nor can it. Left in, this
	# dropped a Khorramshahr locked to a vehicle 1.5 seconds after launch --
	# the target is 68 degrees off a nose pitched up at 60, against a 36 degree
	# seeker -- and with the lock gone it thrust straight on at 300 m/s squared
	# for the whole 140 second burn and passed sixteen hundred kilometres up.
	# The ship case worked only because a hull is not a Tank and never entered
	# this test at all.
	var ballistic: bool = bool(ws.get("loft", false))
	var homes_on_a_thing: bool = (target is Aircraft or target is Tank) \
		and not is_cruise and not ballistic
	_mask_check -= delta
	if _mask_check <= 0.0:
		_mask_check = 0.25
		_masked = homes_on_a_thing and not Sim.line_of_sight(global_position, tpos)
	if _masked:
		_seek_lost += delta
		if _seek_lost > 0.6:
			if Sim.debug_weapons:
				print("[msl] %s dropped %s at age %.1f: terrain masked at %.0f m" % [
					wid, str(target.name), age, dist])
			target = null
		return
	var seeker_ang := rad_to_deg((-global_transform.basis.z).angle_to(los))
	# Only a round homing on something it has to *see* can lose it off the edge
	# of the seeker. A weapon flying to a coordinate is on inertial guidance and
	# has no seeker to point -- and a canister round leaves the tube straight up
	# with its mark ninety degrees off the nose by definition, so this dropped
	# every hypersonic 1.2 seconds after launch and left it flying on ballistic.
	# Measured: mark 27.4 km away, closest approach 26.9 km, into the ground at
	# six seconds.
	if homes_on_a_thing and seeker_ang > ws["seeker_fov"]:
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
	if bool(ws.get("loft", false)):
		# A ballistic round flies an arc, it does not run an intercept. Point
		# the velocity vector at the aim point and let the loft above bend the
		# arc: proportional navigation leads a *moving* target, and leading a
		# patch of ground at Mach four simply carried it four kilometres past.
		var lv := vel.normalized() if vel.length() > 1.0 else -global_transform.basis.z
		accel = ((tpos - global_position).normalized() - lv) \
			* maxf(vel.length(), 120.0) * 1.1
	if String(ws["kind"]) == "cruise":
		# Sea skimming. A cruise missile does not fly the line to its target: it
		# runs in on the deck, under the horizon of anything looking for it, and
		# only comes up at the very end. Steering straight at a ship from
		# altitude would be a much easier thing to shoot down and would waste
		# the whole point of a weapon with two minutes of fuel.
		# Where the descent has to start, which is set by how much height there
		# is to lose and how slowly this round can change direction, not by a
		# constant. The entry's own figure is a floor: a sea skimmer's pop-up is
		# a tactic and stays what it says.
		var pop: float = float(ws.get("pop", 2600.0))
		if _turn_r > 0.0 and _deck > 0.0:
			pop = maxf(pop, 2.0 * sqrt(_deck * _turn_r))
		# what this shot settled on at launch, not what the entry says in the
		# abstract -- see `_deck`
		var deck: float = _deck if _deck > 0.0 \
			else float(ws.get("cruise_alt", 30.0))
		# Lead the ship. Steering at where it is now leaves the round chasing a
		# moving deck: at four hundred metres a second over the last two and a
		# half kilometres a corvette travels most of its own length, and the
		# warhead went off eight metres off the side instead of against it.
		var lead: Vector3 = tpos
		var tv := Vector3.ZERO
		if "linear_velocity" in target:
			tv = target.linear_velocity
		elif target.has_method("get_velocity"):
			tv = target.call("get_velocity")
		if tv.length_squared() > 0.01:
			var tof: float = dist / maxf(vel.length(), 60.0)
			lead += tv * minf(tof, 14.0)
		# Terrain following, and it has to look at the ground it is about to
		# cross rather than at one point in the distance. Reading the height at
		# a waypoint eighteen hundred metres ahead and flying the straight line
		# to it puts the round through every ridge standing between the two: at
		# sea that never shows, and over land it hit the first hill it met.
		# Along the ground track, not the line of sight. Released high above a
		# target at sea level the sight line points steeply down, so a waypoint
		# "1755 m ahead" along it was barely ahead at all in plan -- the
		# terrain samples covered a few hundred metres of ground and the
		# let-down had almost no horizontal distance to happen over.
		var step: Vector3 = Vector3(lead.x - global_position.x, 0.0,
			lead.z - global_position.z)
		step = step.normalized() if step.length() > 1.0 \
			else -global_transform.basis.z
		# Two distances, and they are not the same thing. How far ahead the
		# round has to *see* is set by how long it takes to do anything about
		# what it finds -- four and a half seconds of flight. How far ahead it
		# steers is limited by the target. Using one number for both collapsed
		# the horizon to a couple of hundred metres just as the round reached
		# the pop-up range, so it ran at the last hill with no warning at all.
		# Four and a half seconds of warning was enough over the rolling country
		# this was written against. It is not enough over a range: a cruise
		# round let down to its run-in height and met ground rising faster than
		# it could climb, and went into a hillside at 695 m with the ridge it
		# had to cross never more than a kilometre and a half ahead of it.
		var sense: float = clampf(vel.length() * 9.0, 1400.0, 6500.0)
		var look: float = sense
		if dist > pop:
			look = minf(sense, maxf(dist - pop, 300.0))
		var clear := -1e9
		# The steepest climb anything ahead demands, not just the highest thing
		# ahead.
		#
		# Taking the maximum ground over the whole horizon and then aiming at
		# the far end of that horizon is what put this round into hillsides: a
		# ridge a kilometre ahead, seen correctly, was answered by aiming at
		# ridge height two and a half kilometres away -- a four degree climb
		# that reaches the right altitude a kilometre and a half *past* the
		# ridge. What matters is height over distance to each thing in the way,
		# and the worst of those is the one to fly.
		var need := -1e9
		# Sampled every 150 m or so, not every 360. Ten probes over three and a
		# half kilometres steps straight over any ridge narrower than the gap
		# between them, and the round then meets ground it never saw coming with
		# no distance left to climb.
		var probes: int = clampi(int(sense / 150.0), 12, 40)
		for k in probes + 1:
			var reach_k: float = sense * float(k) / float(probes)
			var q: Vector3 = global_position + step * reach_k
			var gh: float = maxf(Sim.height_at(q.x, q.z), Sim.WATER_LEVEL)
			clear = maxf(clear, gh)
			if reach_k > 1.0:
				# Against a safety margin, not against the cruising height.
				# These are two different jobs: not hitting the ground, and
				# settling at a chosen altitude. Using the cruise height here
				# meant a round that cruises at six kilometres demanded to be
				# six kilometres above a hilltop five hundred metres ahead --
				# a gradient of one and a half -- and climbed to fourteen.
				need = maxf(need, (gh + minf(deck, 150.0)
					- global_position.y) / reach_k)
		var aim := lead
		# Where it stops holding its terrain clearance and commits at the
		# target. Nine hundred metres is a second and a half for a Kalibr and a
		# third of a second for a Zircon, and no round sheds a hundred and fifty
		# metres of clearance in a third of a second: both of these crossed
		# directly over the ship, a hundred and twenty metres up, which is the
		# floor they were still flying. The distance has to be the one this
		# round needs to get down from that height -- rotating into the descent
		# and out of it again, at whatever radius it turns at.
		var commit: float = 900.0
		if _turn_r > 0.0:
			commit = maxf(commit, 2.0 * sqrt(_crest(deck) * _turn_r))
		if dist > pop:
			var ahead: Vector3 = global_position + step * look
			# Let down at a sensible angle. The waypoint is eighteen hundred
			# metres ahead and the cruise height is thirty, so from a release at
			# three thousand the round was pointed fifty-nine degrees at the
			# ground -- and at four hundred metres a second it cannot pull out
			# of that. It went in twelve kilometres short of the target with the
			# mountain still ahead of it.
			var floor_y: float = clear + deck
			var above: float = global_position.y - floor_y
			# Eased onto the cruise height, not driven at it. A steady
			# twenty degree let-down arrives at thirty metres still going down
			# at a hundred and thirty metres a second, and arresting that takes
			# eighty metres it does not have -- so it flew through the cruise
			# height and into the ground. Letting the descent shrink with the
			# height still to lose gives it a flare instead of an arrival.
			# Aim a fraction of the way down to the cruise height, so the
			# let-down eases off as it arrives instead of driving through it.
			# Scaling by the height it could still pull out of looks more
			# principled and is wrong: the waypoint is most of two kilometres
			# ahead and the round steers at it the whole way, so it does not
			# get to use that pull-out and simply flew into the deck.
			# The constant is what stops the fraction asymptoting: without it
			# the descent halves for ever and a sea skimmer never gets down,
			# which left one cruising in at six hundred metres.
			# Never negative. Below the cruise floor `above` goes negative and
			# took the glide with it, so `position - glide` aimed *above* the
			# round by however far it was down -- a climb command that grew the
			# further behind it got. It overshot a six kilometre cruise height
			# by fourteen and ended up in space.
			var glide: float = maxf(minf(look * 0.36, above * 0.45 + 18.0), 0.0)
			var want_y: float = maxf(floor_y, global_position.y - glide)
			# and never shallower than the nearest thing in the way demands
			if need > 0.0:
				want_y = maxf(want_y, global_position.y + need * look)
			aim = Vector3(ahead.x, want_y, ahead.z)
		elif dist > commit and aim.y < clear + _crest(deck):
			# Even on the run in: a target in the next valley is still behind a
			# ridge, and diving at it from here means diving into the ridge.
			# Inside the last kilometre it commits: a target sitting on the
			# high ground *is* the highest thing ahead, and holding a floor
			# above it flew the round over its head by a hundred and fifty
			# metres.
			aim = Vector3(aim.x, clear + _crest(deck), aim.z)
		var cv := vel.normalized() if vel.length() > 1.0 else -global_transform.basis.z
		var cw := (aim - global_position).normalized()
		accel = (cw - cv) * maxf(vel.length(), 80.0) * 2.0 + Vector3.UP * 9.81
		var cg: float = ws["max_g"] * 9.81
		if accel.length() > cg:
			accel = accel.normalized() * cg
		vel += accel * delta
		return
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
	var k := String(ws["kind"])
	if _last_aim == Vector3.INF:
		return
	var v_dir := vel.normalized() if vel.length() > 1.0 else -global_transform.basis.z
	var want_dir := (_last_aim - global_position).normalized()
	# A bomb and a cruise round steer hard onto the line. A ballistic round
	# trims the arc it is already flying, the same authority its own guidance
	# uses -- hauling one onto the line of sight at 2.6 would have it fighting
	# its own trajectory the whole way down.
	var gain: float = 2.6 if (k == "bomb" or k == "cruise") else 1.1
	var accel := (want_dir - v_dir) * maxf(vel.length(), 90.0) * gain
	var g_max: float = ws["max_g"] * 9.81
	if accel.length() > g_max:
		accel = accel.normalized() * g_max
	vel += accel * _delta

var _last_gap := 1e9
var _mark_best := 1e9
var _split := false


## Let the load go. Each child is thrown off the bus with a little sideways
## velocity, so by the time they are down they cover a footprint rather than
## all arriving at the same point — which would be a very expensive way of
## building one crater.
func _open_up() -> void:
	if _split:
		return
	_split = true
	var _kids: Array = []
	var count: int = int(ws.get("mirv", 0))
	var child: String = String(ws.get("mirv_child", ""))
	if count <= 0 or child == "":
		return
	var spread: float = float(ws.get("mirv_spread", 400.0))
	# how long the children have left to fall decides how much sideways speed
	# it takes to cover the footprint
	var bed: float = maxf(Sim.height_at(global_position.x, global_position.z),
		Sim.WATER_LEVEL)
	var fall: float = sqrt(maxf(2.0 * maxf(global_position.y - bed, 10.0) / 9.81, 0.5))
	var lateral: float = spread / maxf(fall, 0.5)
	var fwd := vel.normalized() if vel.length() > 1.0 else -global_transform.basis.z
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
	var centre: Vector3 = target.global_position if is_instance_valid(target) \
		else global_position
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n.is_in_group("no_lock") or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if ("team" in n) and int(n.team) == team:
			continue
		if (n as Node3D).global_position.distance_to(centre) < spread * 1.6:
			marks.append(n)
	marks.sort_custom(func(x: Node3D, y: Node3D) -> bool:
		return x.global_position.distance_to(centre) \
			< y.global_position.distance_to(centre))
	for i in count:
		var a := TAU * float(i) / float(count) + randf() * 0.3
		var rad: float = lerpf(0.35, 1.0, randf())
		var kick: Vector3 = (right * cos(a) + up * sin(a)) * lateral * rad
		var m := Missile.new()
		var dir: Vector3 = (vel + kick).normalized()
		var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
		var xf := Transform3D(Basis.looking_at(dir, up_ref), global_position)
		# its own warhead, its own target
		var mine: Node = target
		if i < marks.size():
			mine = marks[i]
		elif not marks.is_empty():
			mine = marks[i % marks.size()]
		else:
			# nothing to pick from: spread them over the footprint instead
			var off := Vector3(cos(a), 0.0, sin(a)) * spread * rad
			var pt := _Submark.new()
			pt.team = 1 if team == 0 else 0
			get_tree().current_scene.add_child(pt)
			pt.global_position = centre + off
			mine = pt
		m.launch(child, xf, vel + kick, shooter, mine)
		m.team = team
		get_tree().current_scene.add_child(m)
		_kids.append(m)
	# Hand the camera on. The bus frees itself here, so anything riding it lost
	# its subject the moment the load went — the view cut back to the launcher
	# and you never saw the warheads arrive, which reads as the round simply
	# never landing.
	var scn := get_tree().current_scene
	if scn != null and scn.has_method("hand_weapon_cam") and not _kids.is_empty():
		scn.call("hand_weapon_cam", self, _kids[0])
	if Sim.debug_weapons:
		print("[msl] %s opened at %.0f m: %d x %s over about %.0f m" % [
			wid, global_position.y - bed, count, child, spread])
	Effects.explosion(get_tree().current_scene, global_position, 5.0, false)
	queue_free()



## A patch of ground for one warhead of a cluster, when there is nothing there
## worth naming. Deliberately not lockable and not a radar return.
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

func _hit(what: Node, miss := 0.0) -> void:
	# A detonation out at the edge of the envelope only peppers the target. Two
	# things were wrong with the arithmetic. The miss handed in was measured to
	# the target's origin while the fuse that triggered it was measured to the
	# skin, so against anything large the two disagreed by the length of the
	# ship. And scaling by the fuse radius meant a round always went off close
	# to the edge of its own fuse envelope and therefore always did the floor:
	# a Harpoon against a corvette took a tenth of its hull off. The warhead's
	# lethal radius is what the falloff belongs to.
	var reach: float = float(ws.get("lethal", maxf(float(ws["fuse"]), 1.0)))
	var falloff: float = clampf(1.0 - miss / maxf(reach, 0.1), 0.22, 1.0)
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
		var skin := -1.0
		for n in get_tree().get_nodes_in_group("hittable"):
			if is_instance_valid(n) and str(n.name) == nn and n.has_method("surface_gap"):
				skin = n.call("surface_gap", global_position)
		print("[msl] %s died at age %.1f, %.0f m/s, closest %s at %.1f m (%.1f m off its hull, fuse %.1f), best pass %.1f m at age %.1f" % [
			wid, age, vel.length(), nn, near, skin, float(ws["fuse"]), _min_d, _min_age])
	if Sim.salvo_watch and wid == Sim.salvo_weapon:
		var hitname := "—"
		var hitd := 1e9
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == shooter:
				continue
			var dd: float = n.global_position.distance_to(global_position)
			var rr: float = n.hit_radius() if n.has_method("hit_radius") else 0.0
			if dd - rr < hitd:
				hitd = dd - rr
				hitname = "%s (gap %.0f m, radius %.0f)" % [Sim.label_of(n), dd - rr, rr]
		Sim.salvo_log.append("nearest hittable at death: %s" % hitname)
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
			# Measured to the hull, not to the middle of it. Against a ninety
			# metre ship the centre is forty-five metres from a hit on the bow,
			# so a Harpoon that went off against the side of a corvette was
			# scored as a distant near miss and took a tenth of its hull off.
			var d: float = n.global_position.distance_to(global_position)
			if n.has_method("surface_gap"):
				d = maxf(n.surface_gap(global_position), 0.0)
			elif n.has_method("hit_radius"):
				d = maxf(d - n.hit_radius(), 0.0)
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
	# Something a surface-to-air round can be sent after. Deliberately not
	# "hittable": that group is the radar picture and the lock list, and every
	# round in the air would clutter both. An interceptor reaches its target
	# through the fuse's "always the thing it was sent at" path instead.
	add_to_group("interceptable")

## A missile is a thin-skinned thing at close range: anything that reaches it
## kills it.
func is_alive() -> bool:
	return not dead

func hit_radius() -> float:
	return 2.5

func take_hit(_amount: float, _from: Node = null) -> void:
	if not dead:
		_die(true)
