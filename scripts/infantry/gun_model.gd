class_name GunModel
## What each weapon looks like.
##
## Every long gun was the same three boxes with the numbers changed: a carbine,
## a Kalashnikov and a fifty were one grey brick of different lengths. Each is
## built here from its own side profile -- an outline in the plane of the bore,
## given its thickness -- so the shape that tells one from another across a
## street is the shape it has: the AR's flat top and buffer tube, the AK's dust
## cover and gas tube and curved magazine, the shotgun's wooden wrist, the SCAR's
## long monolithic upper. And each is the colour it is: black, flat dark earth,
## wood, olive.
##
## Weapon space is `Firearm`'s: the muzzle points down -Z, the origin sits on the
## bore line above where the trigger hand closes, and a profile is drawn in
## (z, y). The "Mag" and "Muzzle" nodes are what the rest of the game reaches
## for, and they are where they always were.
##
## Every part's outline is also written down when asked for, which is what the
## kill feed draws its icon from: the picture beside a kill is this gun's own
## silhouette, and cannot drift from it.

const BLACK := Color(0.085, 0.085, 0.09)
const POLY := Color(0.11, 0.11, 0.105)
const PARK := Color(0.17, 0.17, 0.165)
const FDE := Color(0.56, 0.47, 0.33)
const COYOTE := Color(0.50, 0.42, 0.30)
const OD := Color(0.29, 0.31, 0.21)
const WOOD := Color(0.43, 0.24, 0.11)
const PLUM := Color(0.38, 0.17, 0.11)

## Recording: each part's outline goes here instead of into a mesh.
static var _rec_on := false
static var _rec: Array = []
static var _sil_cache := {}
## The surface tools something has been put into: an empty one is not made
## into a mesh.
static var _touched := {}

## The parts of one gun as it is built, by finish.
class Kit:
	var tools := {}
	var mats := {}

	func add(key: String, m: Material) -> void:
		mats[key] = m
		tools[key] = MeshKit.begin()

	func at(key: String) -> SurfaceTool:
		return tools[key]

# --------------------------------------------------------------------- parts
static func _p(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
		i += 2
	return out

## An outline in (z, y), `hw` either side of the bore's plane (or of `x`).
static func slab(st: SurfaceTool, prof: PackedVector2Array, hw: float, x := 0.0) -> void:
	if _rec_on:
		_rec.append(prof)
		return
	_touched[st] = true
	var th := PackedFloat32Array()
	th.resize(prof.size())
	th.fill(hw)
	MeshKit.prism(st, prof, Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0), th,
		Vector3(x, 0, 0))

static func blk(st: SurfaceTool, size: Vector3, at: Vector3) -> void:
	if _rec_on:
		var h := size * 0.5
		_rec.append(_p([at.z - h.z, at.y - h.y, at.z + h.z, at.y - h.y,
			at.z + h.z, at.y + h.y, at.z - h.z, at.y + h.y]))
		return
	_touched[st] = true
	MeshKit.box(st, size, at)

## A round thing along the bore, from z0 to z1 (absolute), centred on `at`'s
## x and y.
static func tube(st: SurfaceTool, r0: float, r1: float, z0: float, z1: float, at: Vector3,
		seg := 10) -> void:
	if _rec_on:
		_rec.append(_p([z0, at.y - r0, z1, at.y - r1, z1, at.y + r1, z0, at.y + r0]))
		return
	_touched[st] = true
	MeshKit.cone(st, r0, r1, z0, z1, Vector3(at.x, at.y, 0.0), seg)

## A magazine seen from the side: its top at `y_top` between `zf` (front) and
## `zr` (rear), `depth` long, and swept forward by `curve` at the bottom.
static func mag_prof(zf: float, zr: float, y_top: float, depth: float, curve: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(zr, y_top))
	out.append(Vector2(zf, y_top))
	for k in [0.35, 0.7, 1.0]:
		var t: float = k
		out.append(Vector2(zf - curve * t * t - (0.004 if t == 1.0 else 0.0), y_top - depth * t))
	for k in [1.0, 0.7, 0.35]:
		var t: float = k
		out.append(Vector2(zr - curve * t * t + (0.003 if t == 1.0 else 0.0), y_top - depth * t))
	return out

## A Picatinny rail from z0 to z1 along y, seen from the side: square teeth.
static func rail(st: SurfaceTool, z0: float, z1: float, y: float, hw := 0.011) -> void:
	var a: float = maxf(z0, z1)
	var b: float = minf(z0, z1)
	var pts: Array = [a, y, a, y + 0.006]
	var z: float = a
	var up := true
	while z - 0.0052 > b:
		z -= 0.0052
		if up:
			pts.append_array([z, y + 0.006, z, y + 0.010])
		else:
			pts.append_array([z, y + 0.010, z, y + 0.006])
		up = not up
	pts.append_array([b, y + (0.010 if not up else 0.006), b, y])
	slab(st, _p(pts), hw)

static func pistol_grip(st: SurfaceTool, steep := 1.0, hw := 0.016) -> void:
	var s: float = 0.30 * steep
	slab(st, _p([0.030, -0.040, 0.066, -0.040, 0.066 + 0.098 * s, -0.138,
		0.030 + 0.098 * s, -0.146, 0.022 + 0.04 * s, -0.09]), hw)

static func trigger_guard(st: SurfaceTool, y := -0.055) -> void:
	blk(st, Vector3(0.010, 0.005, 0.058), Vector3(0, y - 0.023, -0.004))
	blk(st, Vector3(0.010, 0.026, 0.006), Vector3(0, y - 0.012, -0.033))
	blk(st, Vector3(0.004, 0.018, 0.006), Vector3(0, y - 0.010, 0.004))

## The sight the man has fitted, on top of whatever this gun has to sit it on.
## `front_z` is where an iron front post goes, `base` the top of what it stands on.
static func sights(k: Kit, g: Dictionary, front_z: float, base: float) -> void:
	var st := k.at("metal")
	var sy: float = g["sight"]
	if g.get("scope", false) and String(g.get("reticle", "cross")) == "chevron":
		# the prism: short, squat, and square-shouldered on its mount
		tube(st, 0.024, 0.024, -0.15, 0.03, Vector3(0, sy, 0), 8)
		tube(st, 0.029, 0.029, -0.18, -0.15, Vector3(0, sy, 0), 8)
		blk(st, Vector3(0.040, 0.030, 0.11), Vector3(0, sy - 0.012, -0.06))
		blk(st, Vector3(0.022, sy - base, 0.10), Vector3(0, (sy + base) * 0.5 - 0.01, -0.06))
	elif g.get("scope", false) and String(g.get("reticle", "cross")) == "ring":
		tube(st, 0.022, 0.022, -0.11, 0.01, Vector3(0, sy, 0), 8)
		tube(st, 0.026, 0.026, -0.13, -0.11, Vector3(0, sy, 0), 8)
		blk(st, Vector3(0.020, sy - base, 0.08), Vector3(0, (sy + base) * 0.5 - 0.01, -0.05))
	elif g.get("scope", false):
		# a long tube with a bell at each end and two rings holding it
		tube(st, 0.016, 0.016, -0.19, 0.05, Vector3(0, sy, 0), 10)
		tube(st, 0.027, 0.020, -0.27, -0.19, Vector3(0, sy, 0), 10)
		tube(st, 0.020, 0.024, 0.05, 0.10, Vector3(0, sy, 0), 10)
		blk(st, Vector3(0.008, 0.026, 0.020), Vector3(0.022, sy, -0.06))
		for rz in [-0.13, 0.0]:
			blk(st, Vector3(0.036, sy - base + 0.004, 0.018), Vector3(0, (sy + base) * 0.5, rz))
	elif g.get("dot", false):
		# a window to look through: two posts and a hood, open in the middle
		for sx in [-1.0, 1.0]:
			blk(st, Vector3(0.005, 0.040, 0.045), Vector3(sx * 0.019, sy - 0.006, -0.05))
		blk(st, Vector3(0.043, 0.005, 0.045), Vector3(0, sy + 0.016, -0.05))
		blk(st, Vector3(0.043, maxf(sy - 0.026 - base, 0.006), 0.06),
			Vector3(0, (sy - 0.026 + base) * 0.5, -0.05))
	else:
		# a post at the front and an aperture at the back, each on its stem
		blk(st, Vector3(0.004, 0.014, 0.004), Vector3(0, sy - 0.007, front_z))
		blk(st, Vector3(0.012, maxf(sy - 0.014 - base, 0.004), 0.012),
			Vector3(0, (sy - 0.014 + base) * 0.5, front_z))
		blk(st, Vector3(0.020, maxf(sy - base, 0.006), 0.010),
			Vector3(0, (sy + base) * 0.5 - 0.004, 0.06))

# ------------------------------------------------------------------- the guns
static func build(g: Dictionary, quiet := false) -> Node3D:
	var root := Node3D.new()
	root.name = String(g["id"])
	var k := Kit.new()
	k.add("metal", MeshKit.mat(BLACK, 0.48, 0.45))
	k.add("dark", MeshKit.mat(PARK, 0.6, 0.3))
	k.add("furn", MeshKit.mat(POLY, 0.82, 0.04))
	k.add("mag", MeshKit.mat(BLACK, 0.6, 0.3))
	var id := String(g["id"])
	match id:
		"carbine":
			_ar(k, g, false)
		"dmr":
			k.mats["furn"] = MeshKit.mat(FDE, 0.8, 0.03)
			_ar(k, g, true)
		"scar":
			k.mats["furn"] = MeshKit.mat(FDE, 0.78, 0.04)
			k.mats["dark"] = MeshKit.mat(FDE.darkened(0.08), 0.6, 0.1)
			_scar(k, g)
		"ak":
			k.mats["dark"] = MeshKit.mat(Color(0.13, 0.13, 0.135), 0.5, 0.5)
			k.mats["mag"] = MeshKit.mat(PLUM, 0.7, 0.02)
			_ak(k, g)
		"smg":
			_mp7(k, g)
		"vector":
			_vector(k, g)
		"shotgun":
			k.mats["furn"] = MeshKit.mat(WOOD, 0.62, 0.02)
			_m870(k, g)
		"aa20":
			_aa20(k, g)
		"lmg":
			k.mats["mag"] = MeshKit.mat(OD, 0.9, 0.0)
			_saw(k, g)
		"minigun":
			_minigun(k, g)
		"sniper":
			k.mats["furn"] = MeshKit.mat(COYOTE, 0.8, 0.03)
			_m2010(k, g)
		"fifty":
			k.mats["furn"] = MeshKit.mat(PARK, 0.7, 0.2)
			_m107(k, g)
		"pistol":
			k.mats["furn"] = MeshKit.mat(COYOTE, 0.75, 0.03)
			_pistol(k, g, false)
		"glock":
			_pistol(k, g, true)
		"law":
			k.mats["furn"] = MeshKit.mat(OD.lightened(0.08), 0.85, 0.02)
			_at4(k, g)
		"stinger":
			k.mats["furn"] = MeshKit.mat(OD.darkened(0.1), 0.8, 0.04)
			_stinger(k, g)
		"gl":
			k.mats["furn"] = MeshKit.mat(OD, 0.8, 0.04)
			_mgl(k, g)
		"mortar":
			k.mats["furn"] = MeshKit.mat(OD.darkened(0.15), 0.8, 0.04)
			_mortar(k, g)
		_:
			_ar(k, g, false)
	if _rec_on:
		return null
	var can: bool = quiet and Firearm.can_suppress(g)
	var bore_y: float = 0.014 if g.get("hand", false) else 0.004
	if can:
		tube(k.at("metal"), 0.021, 0.021, Firearm.muzzle_z(g) + 0.01 - Firearm.CAN_LEN,
			Firearm.muzzle_z(g) + 0.01, Vector3(0, bore_y, 0), 10)
	# a shotgun's muzzle device, past the end of the barrel
	var dev_len := 0.0
	var mzz: float = Firearm.muzzle_z(g)
	match String(g.get("choke", "none")):
		"choke":
			dev_len = 0.045
			tube(k.at("metal"), 0.0145, 0.0145, mzz + 0.005, mzz - dev_len, Vector3(0, bore_y, 0), 10)
			tube(k.at("metal"), 0.0160, 0.0160, mzz - dev_len + 0.012, mzz - dev_len,
				Vector3(0, bore_y, 0), 10)
		"duckbill":
			# flat and wide: the bore squeezed into a slot across
			dev_len = 0.075
			blk(k.at("metal"), Vector3(0.026, 0.024, 0.02), Vector3(0, bore_y, mzz - 0.005))
			slab(k.at("metal"), _p([mzz - 0.01, bore_y - 0.011, mzz - dev_len, bore_y - 0.006,
				mzz - dev_len, bore_y + 0.006, mzz - 0.01, bore_y + 0.011]), 0.026)
	for key in ["metal", "dark", "furn"]:
		if not _touched.has(k.at(key)):
			continue
		root.add_child(MeshKit.mi(MeshKit.finish(k.at(key), k.mats[key]),
			{"metal": "Metal", "dark": "Receiver", "furn": "Furniture"}[key]))
	if g.get("dot", false):
		# the dot itself: small, bright, and the only lit thing on the weapon
		var dm := MeshKit.begin()
		MeshKit.box(dm, Vector3(0.0035, 0.0035, 0.001), Vector3(0, float(g["sight"]), -0.05))
		var lit := MeshKit.mat(Color(1.0, 0.1, 0.05), 0.4, 0.0, Color(1.0, 0.12, 0.05))
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.add_child(MeshKit.mi(MeshKit.finish(dm, lit), "Dot"))
	var mag := Node3D.new()
	mag.name = "Mag"
	root.add_child(mag)
	if _touched.has(k.at("mag")):
		mag.add_child(MeshKit.mi(MeshKit.finish(k.at("mag"), k.mats["mag"]), "M"))
	_touched.clear()
	for c in root.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0.0, bore_y, Firearm.muzzle_z(g) - (Firearm.CAN_LEN if can else 0.0)
		- dev_len)
	root.add_child(mz)
	return root

## The side view of a weapon, for an icon: every part's outline in (z, y),
## built once for each and kept. Uses the table's own sight, not anybody's
## fitting of it.
static func silhouette(id: String) -> Array:
	if _sil_cache.has(id):
		return _sil_cache[id]
	_rec_on = true
	_rec = []
	var g: Dictionary = Firearm.spec(id)
	if Firearm.index_of(id) == 0 and id != "carbine":
		_rec_on = false
		return []
	build(g, false)
	_rec_on = false
	var out: Array = _rec
	_rec = []
	_sil_cache[id] = out
	return out

# --------------------------------------------------------------- AR family
## The M4 and, longer and heavier and in flat dark earth, the M110.
static func _ar(k: Kit, g: Dictionary, heavy: bool) -> void:
	var m := k.at("metal")
	var d := k.at("dark")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	var hw: float = 0.024 if heavy else 0.021
	# upper: flat top, ejection port side, forward assist
	slab(d, _p([0.095, -0.016, 0.095, 0.030, -0.11, 0.030, -0.11, -0.016]), hw)
	rail(m, 0.09, -0.11, 0.030)
	blk(m, Vector3(0.032, 0.008, 0.02), Vector3(0, 0.026, 0.102))
	blk(m, Vector3(0.012, 0.014, 0.028), Vector3(hw + 0.004, 0.016, 0.058))
	blk(m, Vector3(0.004, 0.016, 0.05), Vector3(hw + 0.001, 0.006, -0.03))
	# lower, magazine well and grip
	slab(d, _p([0.085, -0.016, -0.108, -0.016, -0.108, -0.064, -0.046, -0.064,
		-0.036, -0.050, 0.060, -0.050, 0.085, -0.030]), hw + 0.001)
	pistol_grip(f)
	trigger_guard(m)
	# buffer tube and stock
	var b: float = 0.09 + sk
	tube(m, 0.0155, 0.0155, 0.085, b - 0.02, Vector3(0, 0.002, 0), 10)
	if heavy:
		slab(f, _p([0.10, 0.026, b, 0.032, b, -0.105, b - 0.035, -0.105,
			b - 0.08, -0.06, 0.12, -0.040, 0.10, -0.030]), 0.021)
	else:
		slab(f, _p([b - 0.135, 0.024, b, 0.028, b, -0.092, b - 0.024, -0.092,
			b - 0.135, -0.026]), 0.020)
	blk(m, Vector3(0.044, 0.124, 0.012), Vector3(0, -0.032, b - 0.006))
	# handguard, rail on it, barrel and what is on the end
	var hg_end: float = -0.11 - ln * (0.62 if heavy else 0.47)
	tube(f, 0.027, 0.027, -0.11, hg_end, Vector3(0, 0.002, 0), 8)
	rail(m, -0.112, hg_end, 0.030)
	tube(m, 0.011 if heavy else 0.0095, 0.0095, hg_end, -ln + 0.035, Vector3(0, 0.004, 0), 8)
	var fsb: float = hg_end - 0.025
	if not heavy:
		# the A-frame front sight base: gas block and post in one
		slab(m, _p([fsb + 0.018, -0.012, fsb - 0.018, -0.012, fsb - 0.006, 0.030,
			fsb + 0.006, 0.030]), 0.011)
	tube(m, 0.012, 0.012, -ln + 0.035, -ln - 0.02, Vector3(0, 0.004, 0), 8)
	slab(k.at("mag"), mag_prof(-0.103, -0.049, -0.03, float(g["mag_len"]) + 0.03,
		0.008 if heavy else 0.026), 0.013)
	sights(k, g, fsb if not heavy else -ln + 0.06, 0.040)

static func _scar(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var d := k.at("dark")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	# the long upper, rail all the way, and the charging handle on the side
	var fr: float = -0.11 - ln * 0.46
	slab(d, _p([0.095, -0.018, 0.095, 0.032, fr, 0.032, fr, 0.0, fr + 0.03, -0.026,
		-0.11, -0.026, -0.11, -0.018]), 0.024)
	rail(m, 0.09, fr, 0.032)
	blk(m, Vector3(0.018, 0.012, 0.022), Vector3(-0.032, 0.014, -0.17))
	for side in [-1.0, 1.0]:
		blk(m, Vector3(0.006, 0.012, 0.12), Vector3(side * 0.026, 0.0, fr + 0.08))
	slab(f, _p([0.090, -0.018, -0.108, -0.018, -0.108, -0.066, -0.046, -0.066,
		-0.036, -0.052, 0.060, -0.052, 0.088, -0.030]), 0.023)
	pistol_grip(f, 1.0, 0.017)
	trigger_guard(m)
	# the folding stock: a hinge, a comb and an adjustable cheek
	var b: float = 0.09 + sk
	slab(f, _p([0.090, 0.028, b - 0.03, 0.034, b, 0.030, b, -0.098, b - 0.026, -0.098,
		b - 0.07, -0.042, 0.120, -0.034, 0.090, -0.020]), 0.021)
	blk(m, Vector3(0.046, 0.128, 0.012), Vector3(0, -0.034, b - 0.006))
	tube(m, 0.010, 0.010, fr, -ln + 0.035, Vector3(0, 0.004, 0), 8)
	blk(m, Vector3(0.022, 0.034, 0.024), Vector3(0, 0.006, fr - 0.04))
	tube(m, 0.013, 0.013, -ln + 0.035, -ln - 0.02, Vector3(0, 0.004, 0), 8)
	slab(k.at("mag"), mag_prof(-0.103, -0.050, -0.032, float(g["mag_len"]) + 0.03, 0.006),
		0.014)
	sights(k, g, fr - 0.01, 0.042)

static func _ak(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var d := k.at("dark")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	# receiver: a stamped box with the dust cover rounded over the top of it
	slab(d, _p([0.100, -0.046, 0.100, 0.008, 0.086, 0.024, 0.040, 0.030, -0.085, 0.030,
		-0.120, 0.022, -0.120, -0.046]), 0.019)
	# the long safety lever down the right side, and the rear sight block
	blk(m, Vector3(0.004, 0.010, 0.095), Vector3(0.021, -0.004, 0.028))
	slab(d, _p([-0.120, 0.004, -0.160, 0.004, -0.160, 0.028, -0.120, 0.036]), 0.016)
	blk(m, Vector3(0.016, 0.010, 0.08), Vector3(0, 0.036, -0.155))
	# gas tube and the upper handguard over it, the lower handguard round the barrel
	tube(f, 0.013, 0.013, -0.165, -0.33, Vector3(0, 0.026, 0), 8)
	slab(f, _p([-0.150, 0.012, -0.335, 0.012, -0.335, -0.016, -0.310, -0.034,
		-0.165, -0.034, -0.150, -0.022]), 0.024)
	slab(m, _p([-0.335, -0.012, -0.365, -0.012, -0.365, 0.042, -0.335, 0.042]), 0.013)
	tube(m, 0.0085, 0.0085, -0.335, -ln + 0.045, Vector3(0, 0.004, 0), 8)
	# the front sight: a block with ears round the post
	var fz: float = -ln + 0.06
	slab(m, _p([fz + 0.015, -0.010, fz - 0.015, -0.010, fz - 0.012, 0.012, fz - 0.004, 0.044,
		fz + 0.004, 0.044, fz + 0.012, 0.012]), 0.012)
	# the AK-74's muzzle brake: a fat can with the end cut square
	tube(m, 0.0125, 0.0125, -ln + 0.045, -ln - 0.02, Vector3(0, 0.004, 0), 10)
	tube(m, 0.014, 0.014, -ln - 0.008, -ln - 0.02, Vector3(0, 0.004, 0), 10)
	pistol_grip(f, 0.75, 0.017)
	blk(m, Vector3(0.010, 0.005, 0.058), Vector3(0, -0.075, -0.002))
	blk(m, Vector3(0.010, 0.026, 0.006), Vector3(0, -0.062, -0.031))
	blk(m, Vector3(0.004, 0.018, 0.006), Vector3(0, -0.060, 0.006))
	# the folding solid stock, dropping away from the line of the bore
	var b: float = 0.10 + sk
	slab(f, _p([0.100, 0.004, b, -0.010, b, -0.118, b - 0.03, -0.118, b - 0.07, -0.10,
		0.100, -0.046]), 0.019)
	blk(m, Vector3(0.042, 0.112, 0.010), Vector3(0, -0.064, b - 0.004))
	# and the magazine: curved hard enough to see from across a street
	slab(k.at("mag"), mag_prof(-0.112, -0.060, -0.040, float(g["mag_len"]) + 0.015, 0.06),
		0.014)
	if not g.get("scope", false) and not g.get("dot", false):
		# the tangent sight on the block does the job of the rear aperture
		blk(m, Vector3(0.014, maxf(float(g["sight"]) - 0.036, 0.004), 0.012),
			Vector3(0, (float(g["sight"]) + 0.036) * 0.5 - 0.004, -0.14))
		blk(m, Vector3(0.004, 0.012, 0.004), Vector3(0, float(g["sight"]) - 0.006, fz))
	else:
		# a side rail and the mount that reaches over the top from it
		blk(m, Vector3(0.010, 0.030, 0.10), Vector3(-0.024, 0.006, 0.0))
		sights(k, g, fz, 0.034)

static func _mp7(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	# the whole receiver is polymer: tall at the back, sloped off at the front
	slab(f, _p([0.105, -0.026, 0.105, 0.032, -0.098, 0.032, -0.140, 0.012, -0.140, -0.034,
		-0.070, -0.048, 0.030, -0.048, 0.090, -0.040]), 0.022)
	rail(m, 0.098, -0.10, 0.032, 0.010)
	blk(m, Vector3(0.030, 0.010, 0.014), Vector3(0, 0.040, 0.098))
	# the grip the magazine goes up through
	slab(f, _p([0.026, -0.044, 0.078, -0.044, 0.098, -0.145, 0.046, -0.152]), 0.018)
	blk(m, Vector3(0.010, 0.005, 0.054), Vector3(0, -0.080, -0.006))
	blk(m, Vector3(0.010, 0.030, 0.006), Vector3(0, -0.064, -0.033))
	# folding fore grip
	slab(f, _p([-0.128, -0.036, -0.160, -0.036, -0.172, -0.112, -0.142, -0.112]), 0.013)
	tube(m, 0.008, 0.008, -0.140, -ln - 0.005, Vector3(0, 0.004, 0), 8)
	tube(m, 0.0105, 0.0105, -ln + 0.012, -ln - 0.02, Vector3(0, 0.004, 0), 8)
	# the telescoping stock: two rods and a plate
	var b: float = 0.09 + sk
	for sx in [-1.0, 1.0]:
		blk(m, Vector3(0.006, 0.006, b - 0.10), Vector3(sx * 0.016, -0.006, (b + 0.10) * 0.5))
	slab(f, _p([b - 0.024, 0.022, b, 0.022, b, -0.078, b - 0.024, -0.078]), 0.022)
	# the long magazine, standing out of the bottom of the grip
	var ml: float = float(g["mag_len"])
	slab(k.at("mag"), _p([0.034, -0.08, 0.068, -0.08, 0.072 + ml * 0.20, -0.07 - ml,
		0.040 + ml * 0.20, -0.07 - ml]), 0.012)
	sights(k, g, -0.13, 0.042)

static func _vector(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	slab(f, _p([0.100, -0.010, 0.100, 0.030, -0.135, 0.030, -0.135, -0.010]), 0.021)
	rail(m, 0.095, -0.135, 0.030)
	# the lower: the big angled block under the barrel the recoil goes down into
	slab(f, _p([0.100, -0.010, -0.135, -0.010, -0.160, -0.022, -0.160, -0.052, -0.098, -0.104,
		-0.050, -0.080, -0.030, -0.046, 0.100, -0.040]), 0.025)
	slab(f, _p([0.034, -0.038, 0.068, -0.038, 0.094, -0.134, 0.060, -0.140]), 0.016)
	blk(m, Vector3(0.010, 0.005, 0.05), Vector3(0, -0.078, 0.002))
	# barrel shroud, the barrel out of it
	tube(m, 0.015, 0.015, -0.135, -ln + 0.005, Vector3(0, 0.004, 0), 8)
	tube(m, 0.008, 0.008, -ln + 0.005, -ln - 0.02, Vector3(0, 0.004, 0), 8)
	var b: float = 0.09 + sk
	slab(f, _p([0.100, 0.024, b, 0.028, b, -0.078, b - 0.022, -0.078, b - 0.05, -0.014,
		0.100, -0.008]), 0.017)
	var ml: float = float(g["mag_len"])
	slab(k.at("mag"), mag_prof(-0.074, -0.040, -0.06, ml + 0.01, 0.0), 0.012)
	sights(k, g, -0.13, 0.040)

static func _m870(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	# receiver: a steel box with a rounded top edge
	slab(m, _p([0.030, -0.046, 0.030, 0.014, 0.014, 0.024, -0.130, 0.024, -0.142, 0.012,
		-0.142, -0.046]), 0.021)
	blk(m, Vector3(0.010, 0.005, 0.06), Vector3(0, -0.075, -0.004))
	blk(m, Vector3(0.010, 0.030, 0.006), Vector3(0, -0.060, -0.034))
	blk(m, Vector3(0.004, 0.018, 0.006), Vector3(0, -0.058, 0.002))
	blk(m, Vector3(0.010, 0.005, 0.07), Vector3(0, -0.049, 0.0))
	# barrel and the magazine tube under it, the cap on its end
	tube(m, 0.0115, 0.0115, -0.142, -ln - 0.02, Vector3(0, 0.004, 0), 10)
	tube(m, 0.0110, 0.0110, -0.142, -ln * 0.62 - 0.14, Vector3(0, -0.026, 0), 10)
	tube(m, 0.0125, 0.0125, -ln * 0.62 - 0.14, -ln * 0.62 - 0.16, Vector3(0, -0.026, 0), 10)
	blk(m, Vector3(0.010, 0.020, 0.01), Vector3(0, -0.011, -ln * 0.62 - 0.15))
	# the wooden pump, ringed so the hand finds it
	tube(f, 0.0235, 0.0235, -0.255, -0.41, Vector3(0, -0.022, 0), 12)
	for i in 5:
		tube(f, 0.0255, 0.0255, -0.27 - i * 0.03, -0.282 - i * 0.03, Vector3(0, -0.022, 0), 12)
	# the stock: a wooden wrist the hand closes round, a comb and the butt
	var b: float = 0.09 + sk
	slab(f, _p([0.030, 0.014, 0.120, -0.008, b - 0.012, 0.004, b - 0.012, -0.128,
		b - 0.03, -0.130, 0.150, -0.104, 0.090, -0.096, 0.055, -0.088, 0.030, -0.046]), 0.020)
	slab(m, _p([b - 0.012, 0.004, b + 0.006, 0.006, b + 0.006, -0.130, b - 0.012, -0.128]),
		0.022)
	if not g.get("scope", false) and not g.get("dot", false):
		# a bead on the end of the barrel: what a shotgun is aimed with
		tube(m, 0.004, 0.004, -ln + 0.012, -ln + 0.02, Vector3(0, float(g["sight"]) - 0.004, 0), 6)
		blk(m, Vector3(0.004, maxf(float(g["sight"]) - 0.02, 0.004), 0.004),
			Vector3(0, (float(g["sight"]) + 0.012) * 0.5, -ln + 0.016))
	else:
		rail(m, 0.020, -0.13, 0.024)
		sights(k, g, -ln + 0.02, 0.034)

## The automatic shotgun: a long square receiver with the rail along its whole
## top, a short barrel out of the front of it, and the drum hung underneath.
static func _aa20(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var d := k.at("dark")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	slab(d, _p([0.100, -0.022, 0.100, 0.036, -0.330, 0.036, -0.345, 0.020, -0.345, -0.030,
		-0.120, -0.030, -0.110, -0.022]), 0.026)
	rail(m, 0.095, -0.335, 0.036, 0.012)
	# vents down the side of the fore end, and the charging handle
	for i in 5:
		blk(m, Vector3(0.054, 0.010, 0.022), Vector3(0, 0.004, -0.17 - i * 0.034))
	blk(m, Vector3(0.012, 0.012, 0.02), Vector3(-0.03, 0.020, -0.24))
	slab(f, _p([0.085, -0.022, -0.112, -0.022, -0.112, -0.064, -0.050, -0.064, -0.040, -0.052,
		0.060, -0.052, 0.085, -0.034]), 0.024)
	pistol_grip(f, 1.0, 0.017)
	trigger_guard(m)
	tube(m, 0.0135, 0.0135, -0.345, -ln - 0.02, Vector3(0, 0.004, 0), 10)
	blk(m, Vector3(0.016, 0.030, 0.016), Vector3(0, 0.024, -ln + 0.01))
	var b: float = 0.10 + sk
	slab(f, _p([0.100, 0.030, b, 0.030, b, -0.105, b - 0.030, -0.105, b - 0.07, -0.05,
		0.120, -0.040, 0.100, -0.022]), 0.022)
	blk(m, Vector3(0.046, 0.137, 0.012), Vector3(0, -0.037, b - 0.006))
	# the drum: a neck into the well, and the round magazine under it
	var mz := -0.076
	var rr: float = 0.032 + float(g["mag_len"]) * 0.33
	slab(k.at("mag"), _p([mz + 0.026, -0.03, mz - 0.026, -0.03, mz - 0.026, -0.072,
		mz + 0.026, -0.072]), 0.014)
	var circ := PackedVector2Array()
	for i in 18:
		var a: float = TAU * float(i) / 18.0
		circ.append(Vector2(mz + cos(a) * rr, -0.066 - rr + sin(a) * rr))
	slab(k.at("mag"), circ, 0.034)
	sights(k, g, -0.32, 0.046)

## Six barrels round a spindle, the motor and the feed behind them, a carry
## handle over the top and a spade grip under -- the juggernaut's gun.
static func _minigun(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var d := k.at("dark")
	var ln: float = g["len"]
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		tube(m, 0.011, 0.011, -0.10, -ln, Vector3(cos(a) * 0.032, 0.004 + sin(a) * 0.032, 0), 6)
	tube(d, 0.050, 0.050, -0.06, -0.14, Vector3(0, 0.004, 0), 10)        # the clamp
	tube(d, 0.046, 0.046, -ln + 0.06, -ln + 0.02, Vector3(0, 0.004, 0), 10)
	blk(d, Vector3(0.10, 0.11, 0.20), Vector3(0, 0.004, 0.04))            # housing
	blk(m, Vector3(0.06, 0.07, 0.10), Vector3(0, -0.02, 0.17))            # motor
	blk(d, Vector3(0.08, 0.10, 0.16), Vector3(-0.09, -0.02, 0.04))        # feed chute
	blk(m, Vector3(0.02, 0.10, 0.02), Vector3(0, 0.08, -0.05))            # handle
	blk(m, Vector3(0.02, 0.10, 0.02), Vector3(0, 0.08, 0.10))
	blk(m, Vector3(0.02, 0.02, 0.17), Vector3(0, 0.13, 0.025))

static func _saw(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var d := k.at("dark")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	# the receiver, and the feed cover hinged over the top of it
	slab(d, _p([0.090, -0.052, 0.090, 0.034, -0.172, 0.034, -0.172, -0.052]), 0.030)
	slab(m, _p([0.070, 0.034, -0.125, 0.034, -0.125, 0.046, -0.100, 0.052, 0.050, 0.052,
		0.070, 0.046]), 0.028)
	rail(m, 0.04, -0.10, 0.052, 0.010)
	blk(m, Vector3(0.014, 0.016, 0.03), Vector3(0.034, 0.010, -0.02))
	# handguard below the barrel, barrel with its heat shield and carrying handle
	slab(f, _p([-0.172, -0.004, -0.335, -0.004, -0.335, -0.034, -0.320, -0.046,
		-0.172, -0.046]), 0.023)
	tube(m, 0.011, 0.011, -0.172, -ln + 0.03, Vector3(0, 0.004, 0), 8)
	slab(m, _p([-0.180, 0.016, -0.360, 0.016, -0.360, 0.024, -0.180, 0.024]), 0.012)
	slab(m, _p([-0.180, 0.020, -0.180, 0.070, -0.300, 0.070, -0.300, 0.020, -0.286, 0.020,
		-0.286, 0.058, -0.194, 0.058, -0.194, 0.020]), 0.006)
	# gas block, front post, and the bipod folded forward under the barrel
	slab(m, _p([-0.400, -0.030, -0.430, -0.030, -0.430, 0.020, -0.418, 0.046,
		-0.412, 0.046, -0.400, 0.020]), 0.013)
	for sx in [-1.0, 1.0]:
		blk(m, Vector3(0.006, 0.006, 0.17), Vector3(sx * 0.013, -0.024, -0.445))
	tube(m, 0.013, 0.013, -ln + 0.03, -ln - 0.02, Vector3(0, 0.004, 0), 8)
	pistol_grip(f, 1.0, 0.017)
	trigger_guard(m)
	# the skeleton stock
	var b: float = 0.09 + sk
	slab(f, _p([0.090, 0.022, b, 0.026, b, -0.115, b - 0.030, -0.115, 0.120, -0.052,
		0.090, -0.052]), 0.022)
	blk(m, Vector3(0.046, 0.142, 0.012), Vector3(0, -0.044, b - 0.006))
	# the box of belt hung under the left side
	var ml: float = float(g["mag_len"])
	slab(k.at("mag"), _p([-0.012, -0.030, -0.112, -0.030, -0.116, -0.034 - ml,
		-0.008, -0.034 - ml]), 0.036, -0.022)
	sights(k, g, -0.415, 0.052)

static func _m2010(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	# a round bolt action sat in a chassis, the bolt handle out to the right
	tube(m, 0.020, 0.020, 0.085, -0.13, Vector3(0, 0.004, 0), 12)
	blk(m, Vector3(0.048, 0.010, 0.010), Vector3(0.036, 0.0, 0.055))
	blk(m, Vector3(0.018, 0.018, 0.018), Vector3(0.062, -0.010, 0.055))
	rail(m, 0.075, -0.125, 0.024, 0.010)
	slab(f, _p([0.090, -0.012, -0.130, -0.012, -0.130, -0.050, -0.060, -0.050, -0.050, -0.060,
		0.090, -0.054]), 0.026)
	tube(f, 0.028, 0.028, -0.13, -0.47, Vector3(0, 0.004, 0), 8)
	rail(m, -0.135, -0.46, 0.032, 0.010)
	pistol_grip(f, 1.0, 0.017)
	trigger_guard(m, -0.06)
	tube(m, 0.0105, 0.0105, -0.47, -ln + 0.07, Vector3(0, 0.004, 0), 8)
	tube(m, 0.017, 0.017, -ln + 0.07, -ln - 0.02, Vector3(0, 0.004, 0), 10)
	# the folding stock with its cheek riser, and the monopod under the butt
	var b: float = 0.09 + sk
	slab(f, _p([0.090, 0.010, 0.140, 0.012, 0.152, 0.036, b - 0.035, 0.036, b, 0.030,
		b, -0.112, b - 0.034, -0.112, b - 0.05, -0.052, 0.120, -0.042, 0.090, -0.042]), 0.021)
	blk(m, Vector3(0.012, 0.050, 0.012), Vector3(0, -0.082, b - 0.06))
	blk(m, Vector3(0.046, 0.146, 0.012), Vector3(0, -0.040, b - 0.004))
	slab(k.at("mag"), mag_prof(-0.098, -0.046, -0.05, float(g["mag_len"]) + 0.012, 0.0), 0.016)
	sights(k, g, -0.40, 0.034)

static func _m107(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var d := k.at("dark")
	var f := k.at("furn")
	var ln: float = g["len"]
	var sk: float = g["stock"]
	# a big square upper the barrel recoils into, and the lower under it
	slab(d, _p([0.100, -0.014, 0.100, 0.048, -0.300, 0.048, -0.300, -0.014]), 0.031)
	rail(m, 0.095, -0.295, 0.048, 0.012)
	slab(d, _p([0.100, -0.014, -0.125, -0.014, -0.125, -0.078, -0.050, -0.078, -0.040, -0.062,
		0.100, -0.062]), 0.030)
	# the fluted barrel, the carrying handle and the bipod folded under it
	tube(m, 0.017, 0.017, -0.30, -ln + 0.09, Vector3(0, 0.004, 0), 12)
	slab(m, _p([-0.24, 0.048, -0.24, 0.092, -0.36, 0.092, -0.36, 0.030, -0.345, 0.030,
		-0.345, 0.080, -0.255, 0.080, -0.255, 0.048]), 0.007)
	for sx in [-1.0, 1.0]:
		blk(m, Vector3(0.009, 0.009, 0.32), Vector3(sx * 0.022, -0.030, -0.48))
	blk(m, Vector3(0.05, 0.020, 0.03), Vector3(0, -0.012, -0.32))
	# the muzzle brake: two chambers, a slab with the sides cut away
	slab(m, _p([-ln + 0.09, -0.022, -ln - 0.02, -0.022, -ln - 0.02, 0.030, -ln + 0.09, 0.030]),
		0.030)
	for zc in [-ln + 0.06, -ln + 0.01]:
		blk(m, Vector3(0.064, 0.036, 0.018), Vector3(0, 0.004, zc))
	pistol_grip(f, 1.0, 0.019)
	trigger_guard(m, -0.07)
	# stock and the rear grip under it
	var b: float = 0.10 + sk
	slab(f, _p([0.100, 0.044, b, 0.050, b, -0.135, b - 0.040, -0.135, b - 0.075, -0.062,
		0.100, -0.062]), 0.028)
	slab(f, _p([b - 0.11, -0.060, b - 0.07, -0.060, b - 0.08, -0.135, b - 0.11, -0.135]), 0.014)
	blk(m, Vector3(0.060, 0.19, 0.016), Vector3(0, -0.042, b - 0.006))
	slab(k.at("mag"), mag_prof(-0.118, -0.046, -0.07, float(g["mag_len"]) + 0.02, 0.0), 0.024)
	sights(k, g, -0.36, 0.058)

static func _pistol(k: Kit, g: Dictionary, glock: bool) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	# the slide: cocking serrations at the back, the front bevelled down
	var sf: float = -ln - 0.012
	slab(m, _p([0.055, -0.001, 0.055, 0.031, 0.040, 0.033, sf + 0.008, 0.033, sf, 0.024,
		sf, -0.001]), 0.013 if not glock else 0.0135)
	for i in 4:
		blk(m, Vector3(0.028, 0.026, 0.0025), Vector3(0, 0.016, 0.046 - i * 0.006))
	tube(m, 0.0065, 0.0065, sf, -ln - 0.02, Vector3(0, 0.014, 0), 8)
	if glock:
		# the compensator cuts in the top of the slide
		blk(m, Vector3(0.020, 0.006, 0.008), Vector3(0, 0.034, sf + 0.016))
	blk(m, Vector3(0.004, 0.008, 0.006), Vector3(0, 0.037, sf + 0.008))
	blk(m, Vector3(0.018, 0.008, 0.006), Vector3(0, 0.037, 0.045))
	# the frame: dust cover with its rail, the trigger guard, the grip
	var gf: float = 0.018 if not glock else 0.022
	var gb: float = 0.068 if not glock else 0.074
	slab(f, _p([0.062, -0.002, -ln + 0.004, -0.002, -ln + 0.004, -0.020, -0.034, -0.020,
		-0.034, -0.026, -0.028, -0.046, 0.000, -0.049, 0.012, -0.036, gf, -0.116,
		gb, -0.116, 0.064, -0.040, 0.074, -0.010]), 0.0145)
	blk(f, Vector3(0.004, 0.012, 0.006), Vector3(0, -0.032, 0.0))
	if glock:
		# thirty three rounds stand well out of the bottom of the grip
		slab(k.at("mag"), _p([gf + 0.004, -0.112, gb - 0.004, -0.112, gb - 0.001, -0.180,
			gf + 0.010, -0.180]), 0.012)

static func _at4(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	# the tube, with a black shock absorber on each end
	tube(f, 0.050, 0.050, -ln + 0.05, 0.36, Vector3.ZERO, 14)
	tube(m, 0.059, 0.059, -ln - 0.03, -ln + 0.05, Vector3.ZERO, 14)
	tube(m, 0.060, 0.074, 0.36, 0.46, Vector3.ZERO, 14)
	for zc in [-0.20, 0.10]:
		tube(f, 0.053, 0.053, zc, zc - 0.012, Vector3.ZERO, 14)
	# the grip and trigger, the fore grip, the shoulder pad and the cocking lever
	blk(m, Vector3(0.030, 0.10, 0.040), Vector3(0, -0.095, 0.04))
	blk(m, Vector3(0.030, 0.080, 0.040), Vector3(0, -0.085, -0.22))
	blk(m, Vector3(0.034, 0.016, 0.12), Vector3(0, -0.056, 0.17))
	blk(m, Vector3(0.012, 0.022, 0.05), Vector3(0.034, 0.048, 0.20))
	# folding sights: a post at the front and a peep at the back
	blk(m, Vector3(0.012, 0.06, 0.05), Vector3(0, float(g["sight"]) - 0.03, -0.05))
	blk(m, Vector3(0.014, 0.05, 0.03), Vector3(0, float(g["sight"]) - 0.025, 0.12))

## The M224 in its handheld fit: the tube, the base plate at the back and the
## trigger grip, carried like a launcher.
static func _mortar(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	tube(f, 0.036, 0.036, -ln + 0.05, 0.30, Vector3.ZERO, 14)
	tube(m, 0.042, 0.042, -ln - 0.01, -ln + 0.06, Vector3.ZERO, 14)
	# the base plate, square on the breech end
	blk(m, Vector3(0.20, 0.20, 0.025), Vector3(0, 0, 0.34))
	# grip and trigger, and the sight on its bracket on the left
	blk(m, Vector3(0.030, 0.10, 0.040), Vector3(0, -0.090, 0.12))
	blk(m, Vector3(0.030, 0.07, 0.040), Vector3(0, -0.075, -0.25))
	blk(m, Vector3(0.040, 0.05, 0.08), Vector3(-0.06, float(g["sight"]) - 0.02, 0.02))

static func _stinger(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	# the launch tube, its frangible front cover, and the back end
	tube(f, 0.040, 0.040, -ln + 0.05, 0.40, Vector3.ZERO, 14)
	tube(m, 0.046, 0.046, -ln - 0.03, -ln + 0.05, Vector3.ZERO, 14)
	tube(m, 0.046, 0.052, 0.38, 0.45, Vector3.ZERO, 14)
	# the gripstock: the hand grip, the battery under it, the sight frame
	blk(m, Vector3(0.034, 0.10, 0.040), Vector3(0, -0.095, 0.04))
	slab(m, _p([0.10, -0.040, -0.22, -0.040, -0.24, -0.070, 0.08, -0.070]), 0.020)
	tube(m, 0.022, 0.022, -0.16, -0.06, Vector3(0, -0.10, 0), 10)
	blk(m, Vector3(0.012, 0.06, 0.05), Vector3(0, float(g["sight"]) - 0.03, -0.05))
	blk(m, Vector3(0.050, 0.014, 0.12), Vector3(-0.05, 0.03, -0.06))
	# the IFF antenna: a grid folded out on the left
	slab(m, _p([-ln + 0.12, 0.02, -ln + 0.26, 0.02, -ln + 0.26, 0.11, -ln + 0.12, 0.11]),
		0.003, -0.07)
	blk(m, Vector3(0.03, 0.012, 0.012), Vector3(-0.055, 0.03, -ln + 0.19))

static func _mgl(k: Kit, g: Dictionary) -> void:
	var m := k.at("metal")
	var f := k.at("furn")
	var ln: float = g["len"]
	# a short fat barrel with its frame, and the revolving drum behind it
	tube(m, 0.030, 0.030, -ln, -0.13, Vector3(0, 0.004, 0), 12)
	tube(m, 0.034, 0.034, -ln - 0.02, -ln + 0.03, Vector3(0, 0.004, 0), 12)
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		tube(f, 0.021, 0.021, -0.13, 0.02, Vector3(cos(a) * 0.040, -0.012 + sin(a) * 0.040, 0), 10)
	tube(m, 0.012, 0.012, -0.135, 0.025, Vector3(0, -0.012, 0), 8)
	blk(m, Vector3(0.020, 0.020, 0.30), Vector3(0, 0.054, -0.12))
	for zc in [-0.14, 0.03]:
		blk(m, Vector3(0.016, 0.080, 0.012), Vector3(0, 0.010, zc))
	# grips, the folding stock and the reflex sight
	blk(f, Vector3(0.034, 0.095, 0.042), Vector3(0, -0.090, 0.07))
	blk(f, Vector3(0.034, 0.080, 0.040), Vector3(0, -0.07, -0.26))
	blk(m, Vector3(0.020, 0.024, 0.22), Vector3(0, -0.02, 0.15))
	slab(f, _p([0.22, 0.010, 0.28, 0.010, 0.28, -0.090, 0.24, -0.090]), 0.020)
	for sx in [-1.0, 1.0]:
		blk(m, Vector3(0.005, 0.036, 0.04), Vector3(sx * 0.018, float(g["sight"]) - 0.006, -0.05))
	blk(m, Vector3(0.041, 0.005, 0.04), Vector3(0, float(g["sight"]) + 0.014, -0.05))
