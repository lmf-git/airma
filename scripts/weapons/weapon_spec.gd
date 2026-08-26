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
	"slbm": {
		"name": "Trident submarine-launched missile", "short": "SLB", "kind": "radar",
		"mass": 5900.0, "length": 13.4, "dia": 2.11, "fin": 0.90,
		"boost": 190.0, "burn": 30.0, "max_g": 14.0, "drag": 0.00012, "ref_speed": 900.0,
		"life": 260.0, "range": 90000.0, "seeker_fov": 180.0, "lock_time": 0.0,
		"arm_time": 8.0, "fuse": 24.0, "damage": 90000.0,
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
