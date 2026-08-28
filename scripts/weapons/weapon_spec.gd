class_name WeaponSpec
## Store database. `kind` drives the seeker logic in Missile.

static func get_spec(id: String) -> Dictionary:
	return _db().get(id, _db()["aim9"])

static func _db() -> Dictionary:
	return {
	"aim9": {
		"name": "AIM-9X", "short": "9X", "kind": "ir",
		"mass": 85.0, "length": 3.02, "dia": 0.127, "fin": 0.32,
		"boost": 320.0, "burn": 5.0, "max_g": 50.0, "drag": 0.00035, "ref_speed": 900.0,
		"life": 32.0, "range": 12000.0, "seeker_fov": 80.0, "lock_time": 0.5,
		"arm_time": 0.35, "fuse": 9.0, "damage": 105.0,
		"colour": Color(0.86, 0.86, 0.83), "band": Color(0.85, 0.55, 0.15),
		"eject": 0.0, "trail": Color(0.9, 0.85, 0.8),
		"flare_bait": 0.55,
		"desc": "Short-range IR. Fire and forget, defeated by flares.",
	},
	"aim120": {
		"name": "AIM-120C", "short": "120", "kind": "radar",
		"mass": 152.0, "length": 3.65, "dia": 0.178, "fin": 0.26,
		"boost": 420.0, "burn": 8.0, "max_g": 35.0, "drag": 0.00028, "ref_speed": 1100.0,
		"life": 75.0, "range": 40000.0, "seeker_fov": 55.0, "lock_time": 1.4,
		"arm_time": 0.6, "fuse": 13.0, "damage": 130.0,
		"colour": Color(0.80, 0.80, 0.78), "band": Color(0.75, 0.72, 0.30),
		"eject": 6.0, "trail": Color(0.85, 0.85, 0.9),
		"flare_bait": 0.0, "chaff_bait": 0.45,
		"desc": "Radar guided BVR. Needs lock until it goes active; chaff will break it.",
	},
	"sm2": {
		# A ship's magazine is not an aeroplane's. A naval round is launched
		# from a standing start with the whole ocean's worth of mass behind it,
		# so it can afford a booster an air-launched missile cannot: it goes
		# faster, it burns longer, it reaches further and it carries a great
		# deal more warhead. Firing AMRAAMs out of a destroyer gave the fleet an
		# air defence that arrived late and did not hurt.
		"name": "SM-2 surface-to-air", "short": "SM2", "kind": "radar",
		"mass": 708.0, "length": 6.55, "dia": 0.343, "fin": 0.62,
		"boost": 620.0, "burn": 16.0, "max_g": 44.0, "drag": 0.00026, "ref_speed": 1550.0,
		"life": 110.0, "range": 74000.0, "seeker_fov": 70.0, "lock_time": 0.6,
		"arm_time": 0.8, "fuse": 22.0, "damage": 290.0,
		"colour": Color(0.86, 0.86, 0.84), "band": Color(0.30, 0.45, 0.70),
		"eject": 0.0, "trail": Color(0.88, 0.88, 0.92),
		"flare_bait": 0.0, "chaff_bait": 0.30,
		"desc": "Fleet area defence. Long reach, heavy warhead; harder to chaff than an AMRAAM.",
	},
	"agm65": {
		# A rocket, and a short-burning one: it is a bomb with a motor to flatten
		# the trajectory, not a cruise weapon.
		"name": "AGM-65 Maverick", "short": "MAV", "kind": "radar",
		"mass": 302.0, "length": 2.49, "dia": 0.305, "fin": 0.71,
		# It was a three and a half second kick behind a drag coefficient that
		# ate it: sixty-seven metres a second squared of deceleration at four
		# hundred metres a second, so it was spent inside seven kilometres and
		# fell in the sea short of anything further. A slimmer body and a longer
		# burn put its reach where the entry has always claimed it was.
		"boost": 250.0, "burn": 5.2, "max_g": 22.0, "drag": 0.00015, "ref_speed": 420.0,
		"life": 60.0, "range": 22000.0, "seeker_fov": 45.0, "lock_time": 0.9,
		"arm_time": 0.6, "fuse": 11.0, "damage": 260.0, "lethal": 26.0,
		"air_to_ground": true,
		"colour": Color(0.80, 0.80, 0.76), "band": Color(0.55, 0.52, 0.30),
		"eject": 3.0, "trail": Color(0.86, 0.85, 0.82),
		"flare_bait": 0.0, "chaff_bait": 0.10,
		"desc": "Rocket powered precision strike. Short reach, heavy warhead.",
	},
	"agm84": {
		# A turbojet: low thrust for a very long time, which is what a cruise
		# weapon is. It runs in low over the sea and only climbs at the end.
		"name": "AGM-84 Harpoon", "short": "HRP", "kind": "cruise",
		"mass": 691.0, "length": 4.63, "dia": 0.343, "fin": 0.83,
		"boost": 46.0, "burn": 240.0, "max_g": 12.0, "drag": 0.00030, "ref_speed": 290.0,
		"life": 300.0, "range": 124000.0, "seeker_fov": 60.0, "lock_time": 1.2,
		"arm_time": 1.5, "fuse": 16.0, "damage": 480.0, "lethal": 30.0,
		"cruise_alt": 28.0, "pop": 2600.0,
		"colour": Color(0.84, 0.84, 0.80), "band": Color(0.30, 0.42, 0.62),
		"eject": 4.0, "trail": Color(0.80, 0.82, 0.86),
		"flare_bait": 0.0, "chaff_bait": 0.22,
		"desc": "Sea skimming anti-ship missile. Runs in on the deck, pops at the end.",
	},
	"agm88": {
		"name": "AGM-88 HARM", "short": "HRM", "kind": "radar",
		"mass": 361.0, "length": 4.17, "dia": 0.254, "fin": 0.44,
		"boost": 520.0, "burn": 9.0, "max_g": 26.0, "drag": 0.00030, "ref_speed": 900.0,
		"life": 90.0, "range": 48000.0, "seeker_fov": 70.0, "lock_time": 0.8,
		"arm_time": 0.8, "fuse": 14.0, "damage": 300.0, "lethal": 24.0,
		"anti_radiation": true, "air_to_ground": true,
		"colour": Color(0.78, 0.78, 0.75), "band": Color(0.70, 0.30, 0.25),
		"eject": 3.0, "trail": Color(0.84, 0.84, 0.86),
		"flare_bait": 0.0, "chaff_bait": 0.0,
		"desc": "Anti-radiation. Homes on a battery's radar; chaff does nothing.",
	},
	# ---------------------------------------------------------- hypersonics
	# All of these are lofted: they climb out of the thick air, run the middle
	# of the flight where there is almost nothing to slow them, and come down
	# very fast and very steep. That is what makes them hard, and it falls out
	# of the flight model rather than being asserted — a low drag coefficient
	# plus `loft` plus a long burn.
	"kalibr": {
		"name": "3M-14 Kalibr", "short": "KLB", "kind": "cruise",
		"mass": 1780.0, "length": 6.20, "dia": 0.533, "fin": 0.90,
		"boost": 42.0, "burn": 280.0, "max_g": 11.0, "drag": 0.00028,
		"ref_speed": 260.0,
		"life": 340.0, "range": 150000.0, "seeker_fov": 60.0, "lock_time": 1.4,
		"arm_time": 2.0, "fuse": 18.0, "damage": 560.0, "lethal": 34.0,
		"cruise_alt": 24.0, "pop": 2400.0,
		"colour": Color(0.72, 0.73, 0.70), "band": Color(0.35, 0.34, 0.32),
		"eject": 4.0, "trail": Color(0.80, 0.82, 0.84),
		"desc": "Long ranged land attack cruise missile. Runs in on the deck.",
	},
	"zircon": {
		"name": "3M22 Zircon", "short": "ZRC", "kind": "radar",
		"mass": 2400.0, "length": 8.40, "dia": 0.60, "fin": 0.80,
		"boost": 210.0, "burn": 90.0, "max_g": 15.0, "drag": 0.00009,
		"ref_speed": 1900.0,
		"life": 220.0, "range": 96000.0, "seeker_fov": 45.0, "lock_time": 1.2,
		"arm_time": 3.0, "fuse": 22.0, "damage": 1500.0, "lethal": 44.0,
		"loft": true,
		"colour": Color(0.30, 0.31, 0.33), "band": Color(0.62, 0.18, 0.14),
		"eject": 3.0, "trail": Color(0.95, 0.86, 0.72),
		"flare_bait": 0.0, "chaff_bait": 0.05,
		"desc": "Anti-ship hypersonic. Very fast, very hard to defeat.",
	},
	"fattah": {
		"name": "Fattah-1", "short": "FTH", "kind": "radar",
		"mass": 3200.0, "length": 12.0, "dia": 0.86, "fin": 1.05,
		"boost": 240.0, "burn": 70.0, "max_g": 12.0, "drag": 0.00010,
		"ref_speed": 1700.0,
		"life": 240.0, "range": 120000.0, "seeker_fov": 40.0, "lock_time": 1.4,
		"arm_time": 4.0, "fuse": 22.0, "damage": 1300.0, "lethal": 40.0,
		"loft": true,
		"colour": Color(0.52, 0.50, 0.44), "band": Color(0.20, 0.42, 0.24),
		"eject": 3.0, "trail": Color(0.92, 0.88, 0.80),
		"flare_bait": 0.0, "chaff_bait": 0.05,
		"desc": "Hypersonic ballistic missile with a manoeuvring head.",
	},
	"oreshnik": {
		"name": "Oreshnik", "short": "ORE", "kind": "radar",
		"mass": 9000.0, "length": 14.5, "dia": 1.60, "fin": 1.10,
		"boost": 260.0, "burn": 110.0, "max_g": 9.0, "drag": 0.00008,
		"ref_speed": 2400.0,
		"life": 320.0, "range": 180000.0, "seeker_fov": 40.0, "lock_time": 1.6,
		"arm_time": 6.0, "fuse": 26.0, "damage": 900.0, "lethal": 60.0,
		"loft": true,
		# it does not arrive as one thing
		"mirv": 6, "mirv_at": 9000.0, "mirv_spread": 900.0, "mirv_child": "orehead",
		"colour": Color(0.34, 0.34, 0.32), "band": Color(0.58, 0.52, 0.16),
		"eject": 0.0, "trail": Color(0.96, 0.92, 0.86),
		"flare_bait": 0.0, "chaff_bait": 0.0,
		"desc": "Intermediate range hypersonic. Splits into six on the way down.",
	},
	"orehead": {
		# one of the six. No motor: it is already going faster than anything
		# with a motor could push it.
		"name": "Oreshnik warhead", "short": "RV", "kind": "radar",
		"mass": 320.0, "length": 1.90, "dia": 0.44, "fin": 0.30,
		"boost": 0.0, "burn": 0.0, "max_g": 8.0, "drag": 0.00011,
		"ref_speed": 2200.0,
		"life": 90.0, "range": 40000.0, "seeker_fov": 60.0, "lock_time": 0.0,
		"arm_time": 1.0, "fuse": 20.0, "damage": 1400.0, "lethal": 90.0,
		"colour": Color(0.28, 0.28, 0.27), "band": Color(0.58, 0.52, 0.16),
		"eject": 0.0, "trail": Color(0.98, 0.90, 0.78),
		"flare_bait": 0.0, "chaff_bait": 0.0,
		"desc": "A re-entry vehicle. Nothing steers it but itself.",
	},
	"cbu97": {
		# a cluster bomb: opens high and lets the load do the work
		"name": "CBU-97 cluster bomb", "short": "CBU", "kind": "bomb",
		"mass": 430.0, "length": 2.34, "dia": 0.40, "fin": 0.32,
		"boost": 0.0, "burn": 0.0, "max_g": 9.0, "drag": 0.00042,
		"ref_speed": 190.0,
		"life": 70.0, "range": 12000.0, "seeker_fov": 180.0, "lock_time": 0.0,
		"arm_time": 1.2, "fuse": 12.0, "damage": 160.0, "lethal": 30.0,
		"mirv": 10, "mirv_at": 700.0, "mirv_spread": 260.0, "mirv_child": "bomblet",
		"colour": Color(0.33, 0.36, 0.31), "band": Color(0.80, 0.66, 0.20),
		"eject": 5.0, "trail": Color(0.8, 0.8, 0.8),
		"flare_bait": 0.0,
		"desc": "Opens at seven hundred metres and scatters ten bomblets.",
	},
	"bomblet": {
		"name": "Cluster bomblet", "short": "BML", "kind": "bomb",
		"mass": 22.0, "length": 0.50, "dia": 0.16, "fin": 0.10,
		"boost": 0.0, "burn": 0.0, "max_g": 5.0, "drag": 0.00090,
		"ref_speed": 90.0,
		"life": 40.0, "range": 3000.0, "seeker_fov": 180.0, "lock_time": 0.0,
		"arm_time": 0.4, "fuse": 8.0, "damage": 260.0, "lethal": 22.0,
		"colour": Color(0.30, 0.33, 0.28), "band": Color(0.80, 0.66, 0.20),
		"eject": 0.0, "trail": Color(0.8, 0.8, 0.8),
		"flare_bait": 0.0,
		"desc": "One of ten. Small, and there are a lot of them.",
	},
	"slbm": {
		"name": "Trident submarine-launched missile", "short": "SLB", "kind": "radar",
		"mass": 5900.0, "length": 13.4, "dia": 2.11, "fin": 0.90,
		"boost": 190.0, "burn": 30.0, "max_g": 14.0, "drag": 0.00012, "ref_speed": 900.0,
		"life": 260.0, "range": 90000.0, "seeker_fov": 180.0, "lock_time": 0.0,
		"arm_time": 8.0, "fuse": 24.0, "damage": 90000.0, "loft": true,
		"colour": Color(0.80, 0.80, 0.78), "band": Color(0.55, 0.10, 0.09),
		"eject": 0.0, "trail": Color(0.92, 0.92, 0.92),
		"flare_bait": 0.0,
		"nuclear": true, "lethal": 4200.0,
	},
	"b83": {
		"name": "B83 strategic nuclear bomb", "short": "STR", "kind": "bomb",
		"mass": 1100.0, "length": 3.66, "dia": 0.46, "fin": 0.42,
		"boost": 0.0, "burn": 0.0, "max_g": 9.0, "drag": 0.00050, "ref_speed": 190.0,
		"life": 160.0, "range": 18000.0, "seeker_fov": 180.0, "lock_time": 0.0,
		"arm_time": 4.0, "fuse": 18.0, "damage": 90000.0,
		"colour": Color(0.80, 0.79, 0.76), "band": Color(0.60, 0.12, 0.10),
		"eject": 3.0, "trail": Color(0.85, 0.85, 0.85),
		"flare_bait": 0.0,
		"nuclear": true, "lethal": 4200.0,
	},
	"b61": {
		"name": "B61-12 tactical nuclear bomb", "short": "NUC", "kind": "bomb",
		"mass": 320.0, "length": 3.58, "dia": 0.33, "fin": 0.30,
		"boost": 0.0, "burn": 0.0, "max_g": 11.0, "drag": 0.00042, "ref_speed": 190.0,
		"life": 120.0, "range": 16000.0, "seeker_fov": 180.0, "lock_time": 0.0,
		"arm_time": 3.0, "fuse": 14.0, "damage": 20000.0,
		"colour": Color(0.78, 0.77, 0.74), "band": Color(0.72, 0.18, 0.14),
		"eject": 4.0, "trail": Color(0.85, 0.85, 0.85),
		"flare_bait": 0.0,
		"nuclear": true, "lethal": 1400.0,
	},
	"gbu32": {
		"name": "GBU-32 JDAM", "short": "JDM", "kind": "bomb",
		"mass": 460.0, "length": 3.05, "dia": 0.36, "fin": 0.34,
		"boost": 0.0, "burn": 0.0, "max_g": 11.0, "drag": 0.00040, "ref_speed": 190.0,
		"life": 70.0, "range": 14000.0, "seeker_fov": 180.0, "lock_time": 0.0,
		"arm_time": 1.2, "fuse": 11.0, "damage": 900.0,
		"colour": Color(0.32, 0.36, 0.30), "band": Color(0.75, 0.72, 0.20),
		"eject": 5.0, "trail": Color(0.8, 0.8, 0.8),
		"flare_bait": 0.0,
		"desc": "1000 lb GPS bomb for ground targets. No motor — loft it.",
	},
	}

## Low-poly store body used both as a carried visual and as the flying round.
static func build_mesh(id: String) -> ArrayMesh:
	var s := get_spec(id)
	var L: float = s["length"]
	var r: float = s["dia"] * 0.5
	var st := MeshKit.begin()
	var half := L * 0.5
	var rings := []
	var profile := [
		[-half, 0.02], [-half + L * 0.10, r * 0.78], [-half + L * 0.20, r],
		[half - L * 0.16, r], [half - L * 0.04, r * 0.86], [half, r * 0.80],
	]
	for p in profile:
		rings.append(MeshKit.ring(p[1], p[1], 0.0, p[0], 2.0, 10))
	MeshKit.loft(st, rings, Vector3.ZERO)
	var fin: float = s["fin"]
	# tail fins + forward control surfaces
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var u := Vector3(cos(a), sin(a), 0.0)
		var v := Vector3(0, 0, 1)
		var poly := PackedVector2Array([
			Vector2(r * 0.8, half - L * 0.20), Vector2(r + fin, half - L * 0.02),
			Vector2(r + fin, half), Vector2(r * 0.8, half)])
		MeshKit.prism(st, poly, u, v, u.cross(v).normalized(),
			PackedFloat32Array([0.014, 0.010, 0.010, 0.014]))
		if s["kind"] != "bomb":
			var poly2 := PackedVector2Array([
				Vector2(r * 0.8, -half + L * 0.26), Vector2(r + fin * 0.62, -half + L * 0.30),
				Vector2(r + fin * 0.62, -half + L * 0.44), Vector2(r * 0.8, -half + L * 0.48)])
			MeshKit.prism(st, poly2, u, v, u.cross(v).normalized(),
				PackedFloat32Array([0.012, 0.009, 0.009, 0.012]))
	var mat := MeshKit.mat(s["colour"], 0.55, 0.10)
	return MeshKit.finish(st, mat)

## How far this weapon can actually get, flown forward with the same arithmetic
## the round itself uses: a quarter second of eject, then thrust while the motor
## burns, then drag against air that thins with height, and gravity throughout.
##
## Comparing the range in the table was not good enough. A Maverick is a three
## and a half second rocket that coasts the rest of the way, so at the 22 km its
## entry claims it runs out of speed and falls in the dirt — while the HUD said
## LOCKED the whole way down. The table's range is what the airframe is sold on;
## this is what it can do from where you actually are.
static func can_reach(w: String, from: Vector3, launch_vel: Vector3,
		to: Vector3) -> bool:
	return reach_time(w, from, launch_vel, to) >= 0.0

## Seconds of flight to arrive, or -1 if it never does.
static func reach_time(w: String, from: Vector3, launch_vel: Vector3,
		to: Vector3) -> float:
	var ws := get_spec(w if w != "gun" else "aim9")
	var pos := from
	var vel := launch_vel
	var life: float = float(ws.get("life", 60.0))
	var burn: float = float(ws.get("burn", 0.0))
	var boost: float = float(ws.get("boost", 0.0))
	var drag: float = float(ws.get("drag", 0.0004))
	var hit: float = maxf(float(ws.get("fuse", 10.0)), 6.0)
	# a cruise weapon flies over the ground, not through it
	var terrain_follows: bool = String(ws.get("kind", "")) == "cruise"
	var dt := 0.25
	var age := 0.0
	while age < life:
		age += dt
		if age < 0.28:
			vel += Vector3.DOWN * 9.81 * dt
			pos += vel * dt
			continue
		var dir: Vector3 = (to - pos).normalized()
		if age - 0.28 < burn:
			# Along its own nose, which follows its velocity -- not along the
			# line to the target. This is most of why the estimate was half as
			# far again as the weapon: fired level at something below you, the
			# motor spends its whole burn pushing along the launch heading while
			# the round is still turning down onto the target, and it is that
			# wasted thrust that decides whether it arrives.
			vel += vel.normalized() * boost * dt
		# What the turn costs. This used to swing the velocity onto the target
		# for free and with no limit, which made it far too hopeful: it said a
		# Maverick reached ten and a half kilometres when the round itself was
		# a kilometre short at nine, and the display promised a lock the weapon
		# could not honour. A fin that makes side force makes drag with it.
		var want_turn: Vector3 = dir - vel.normalized()
		var need: float = want_turn.length() * maxf(vel.length(), 60.0) / maxf(dt, 0.01)
		var g_max: float = float(ws.get("max_g", 20.0)) * 9.81
		var lat: float = minf(need, g_max)
		if lat > 1.0:
			var rho_g: float = 1.225 * exp(-maxf(pos.y, 0.0) / 8500.0) / 1.225
			var q: float = maxf(rho_g * vel.length_squared(), 1.0)
			var bleed: float = float(ws.get("induced", 0.9)) * lat * lat / q * 1000.0
			vel -= vel.normalized() * minf(bleed, vel.length() * 0.25) * dt
		var sp := vel.length()
		var rho: float = 1.225 * exp(-maxf(pos.y, 0.0) / 8500.0)
		vel -= vel.normalized() * drag * rho / 1.225 * sp * sp * dt
		vel += Vector3.DOWN * 9.81 * dt
		# A guided round turns onto the line; flying the launch heading for ever
		# would understate everything fired off boresight.
		var want: float = vel.length()
		# and it may only turn as fast as its own g limit allows
		var turn_rate: float = float(ws.get("max_g", 20.0)) * 9.81 / maxf(vel.length(), 60.0)
		var max_turn: float = turn_rate * dt
		var ang: float = vel.normalized().angle_to(dir)
		var frac: float = clampf(max_turn / maxf(ang, 0.0001), 0.0, 1.0)
		vel = vel.normalized().lerp(dir, frac).normalized() * want
		var was := pos
		pos += vel * dt
		# Against the length travelled, not the point it happened to land on.
		# A quarter of a second at four hundred metres a second is a hundred
		# metre stride, and asking whether that *endpoint* fell inside a sixteen
		# metre capture radius almost always says no — so this reported that
		# nothing could reach anything, the lock was refused, and a Harpoon well
		# inside its range never completed on the glass.
		if Geometry3D.get_closest_point_to_segment(to, was, pos).distance_to(to) < hit:
			# Arriving is not the same as arriving with something left. A
			# Maverick that reaches eight kilometres does so at seventy metres a
			# second, which in practice means it mushes into the sea a couple of
			# hundred metres short and cannot correct for anything. Requiring a
			# usable terminal speed is what makes this agree with the weapon.
			# Where the floor sits is fitted to the weapon rather than argued
			# from first principles: flown against a ship, a Maverick hits at
			# six and seven kilometres and is a kilometre short at eight, and
			# this is the arrival speed that puts the cue on that boundary. The
			# model cannot know what the real round's guidance spends holding
			# its path, so this stands in for it.
			if vel.length() < maxf(float(ws.get("ref_speed", 300.0)) * 0.56, 180.0):
				return -1.0
			return age
		# Into the ground short of it — but only once it is nearly there. This
		# flies the round straight at the target and lets it descend from the
		# first step, which is not what any of these weapons actually do: a
		# cruise round terrain-follows and a rocket is lofted. Failing the shot
		# because *this* idealised path clipped a ridge eighteen kilometres out
		# refused perfectly good launches, and the lock never completed on the
		# glass for a Harpoon well inside its reach.
		if not terrain_follows and pos.distance_to(to) < 2200.0 \
				and pos.y < Sim.height_at(pos.x, pos.z) - 2.0:
			return -1.0
	return -1.0
