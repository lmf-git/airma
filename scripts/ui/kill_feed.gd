class_name KillFeed
## Who killed whom, and with what -- the strip in the top corner.
##
## A kill went into the running log as a sentence, "Viper 3 dropped Hostile 2",
## with nothing to say what did it. Each kill is a line of its own here: the
## killer, a picture of the weapon, a mark for a headshot, and the man it
## killed, each name in its side's colour.
##
## What did it is `cause`: anything that hurts by some means other than a
## bullet -- a grenade, a rocket, a bomb -- says so here for the length of the
## call that deals the damage, and whoever is hit writes it down. A bullet sets
## nothing; it is put down to whatever the man who fired it had in his hands.
##
## The guns are drawn from their own models (`GunModel.silhouette`), so the
## picture in the feed is the weapon you saw him carrying. The rest -- a
## grenade, a burst, a bomb, a vehicle -- are drawn here.

## What is doing the damage right now, or "" for a bullet.
static var cause := ""

## Unit-height outlines of each gun, ready to scale: id -> [aspect, polys].
static var _norm := {}

const TEAM_COL := {0: Color(0.42, 0.76, 1.0), 1: Color(1.0, 0.42, 0.34), -1: Color(0.86, 0.86, 0.86)}

## What hurt him: what the damage says it was, or what the man who did it
## was holding.
static func weapon_of(from: Node) -> String:
	if cause != "":
		return cause
	if from == null or not is_instance_valid(from):
		return "explosion"
	if from is Soldier:
		return (from as Soldier).kit
	if from.has_method("gun_spec"):
		return String((from.call("gun_spec") as Dictionary).get("id", "carbine"))
	if from is Tank:
		return "tank"
	if from is Aircraft:
		return "air"
	return "explosion"

## A name to put in the feed for whoever this is.
static func name_of(n: Node, player: Node = null) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	if player != null and n == player:
		return "YOU"
	if n is Soldier:
		return (n as Soldier).callsign
	if n.has_method("display_name"):
		return String(n.call("display_name"))
	return String(n.name)

static func team_of(n: Node) -> int:
	if n == null or not is_instance_valid(n):
		return -1
	if "team" in n:
		return int(n.get("team"))
	if "side" in n:
		return int(n.get("side"))
	return -1

static func colour(team: int) -> Color:
	return TEAM_COL.get(team, TEAM_COL[-1])

# ---------------------------------------------------------------------- icons
static func _gun(id: String) -> Array:
	if _norm.has(id):
		return _norm[id]
	var polys: Array = GunModel.silhouette(id)
	if polys.is_empty():
		_norm[id] = []
		return []
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in polys:
		for v in (p as PackedVector2Array):
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var h: float = maxf(hi.y - lo.y, 0.001)
	var out: Array = []
	for p in polys:
		var q := PackedVector2Array()
		# muzzle to the right, the way the feed reads: killer, gun, victim
		for v in (p as PackedVector2Array):
			q.append(Vector2((hi.x - v.x) / h, (hi.y - v.y) / h))
		if Geometry2D.triangulate_polygon(q).is_empty():
			continue
		out.append(q)
	var entry: Array = [(hi.x - lo.x) / h, out]
	_norm[id] = entry
	return entry

static func _gun_of(id: String) -> Array:
	return _gun(id) if Firearm.index_of(id) > 0 or id == "carbine" else []

## How wide the icon for `id` is drawn at height `h`. A gun goes by its
## length rather than its height -- a pistol the size of a rifle reads as a
## rifle -- so a fifty is long and a pistol is short.
static func icon_width(id: String, h: float) -> float:
	var gun: Array = _gun_of(id)
	if gun.is_empty():
		return h * 1.6
	return clampf(float(gun[0]) * h * 0.72, h * 1.4, h * 5.0)

## Draw the icon for `id` with its left edge at `at.x`, centred on `at.y`,
## `h` tall. Returns how wide it was.
static func draw_icon(ci: CanvasItem, id: String, at: Vector2, h: float, col: Color) -> float:
	var shade := Color(0, 0, 0, col.a * 0.7)
	var gun: Array = _gun_of(id)
	if not gun.is_empty():
		var aspect: float = gun[0]
		var w: float = icon_width(id, h)
		var s: float = w / aspect
		var top := Vector2(at.x, at.y - s * 0.5)
		for pass_i in 2:
			var c: Color = shade if pass_i == 0 else col
			var off := Vector2(1.2, 1.2) if pass_i == 0 else Vector2.ZERO
			for p in (gun[1] as Array):
				var q := PackedVector2Array()
				for v in (p as PackedVector2Array):
					q.append(top + off + v * s)
				ci.draw_colored_polygon(q, c)
		return w
	var w2: float = icon_width(id, h)
	var c0 := at + Vector2(w2 * 0.5, 0)
	for pass_i in 2:
		var c: Color = shade if pass_i == 0 else col
		var o := c0 + (Vector2(1.2, 1.2) if pass_i == 0 else Vector2.ZERO)
		_shape(ci, id, o, h, c)
	return w2

static func _poly(ci: CanvasItem, o: Vector2, s: float, flat: Array, c: Color) -> void:
	var q := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		q.append(o + Vector2(float(flat[i]), float(flat[i + 1])) * s)
		i += 2
	ci.draw_colored_polygon(q, c)

## The icons that are not guns, each in a box `h` tall centred on `o`. Drawn
## in units of half the height, so (-1, -1) is the top left.
static func _shape(ci: CanvasItem, id: String, o: Vector2, h: float, c: Color) -> void:
	var s: float = h * 0.5
	match id:
		"grenade":
			ci.draw_circle(o + Vector2(0, 0.18) * s, 0.62 * s, c)
			_poly(ci, o, s, [-0.22, -0.55, 0.22, -0.55, 0.22, -0.30, -0.22, -0.30], c)
			_poly(ci, o, s, [0.22, -0.55, 0.62, -0.30, 0.70, 0.30, 0.58, 0.30, 0.50, -0.22, 0.18, -0.42], c)
			ci.draw_arc(o + Vector2(-0.42, -0.62) * s, 0.20 * s, 0.0, TAU, 12, c, maxf(1.0, s * 0.12))
		"tank", "roadkill":
			_poly(ci, o, s, [-1.5, 0.15, 1.5, 0.15, 1.25, 0.70, -1.25, 0.70], c)
			_poly(ci, o, s, [-0.85, 0.15, -0.65, -0.35, 0.45, -0.35, 0.70, 0.15], c)
			_poly(ci, o, s, [0.45, -0.20, 1.75, -0.24, 1.75, -0.12, 0.45, -0.08], c)
		"air", "strafe":
			_poly(ci, o, s, [1.6, 0.0, 1.1, -0.12, -1.2, -0.12, -1.5, -0.05, -1.5, 0.05,
				-1.2, 0.12, 1.1, 0.12], c)
			_poly(ci, o, s, [0.35, -0.10, -0.40, -0.95, -0.70, -0.95, -0.35, -0.10], c)
			_poly(ci, o, s, [0.35, 0.10, -0.40, 0.95, -0.70, 0.95, -0.35, 0.10], c)
			_poly(ci, o, s, [-1.05, -0.10, -1.45, -0.50, -1.60, -0.50, -1.40, -0.05], c)
			_poly(ci, o, s, [-1.05, 0.10, -1.45, 0.50, -1.60, 0.50, -1.40, 0.05], c)
		"strike", "carpet":
			_poly(ci, o, s, [1.1, 0.0, 0.75, -0.30, -0.6, -0.30, -0.85, -0.12, -0.85, 0.12,
				-0.6, 0.30, 0.75, 0.30], c)
			_poly(ci, o, s, [-0.70, -0.20, -1.25, -0.55, -1.25, 0.55, -0.70, 0.20], c)
		"mortar":
			_poly(ci, o, s, [1.0, 0.0, 0.6, -0.34, -0.2, -0.34, -0.55, -0.12, -0.55, 0.12,
				-0.2, 0.34, 0.6, 0.34], c)
			_poly(ci, o, s, [-0.55, -0.10, -1.1, -0.30, -1.1, 0.30, -0.55, 0.10], c)
		"cruise", "missile":
			_poly(ci, o, s, [1.6, 0.0, 1.25, -0.16, -1.3, -0.16, -1.3, 0.16, 1.25, 0.16], c)
			_poly(ci, o, s, [0.1, -0.14, -0.3, -0.62, -0.55, -0.62, -0.35, -0.14], c)
			_poly(ci, o, s, [-1.0, -0.14, -1.35, -0.48, -1.5, -0.48, -1.3, -0.14], c)
			_poly(ci, o, s, [-1.0, 0.14, -1.35, 0.48, -1.5, 0.48, -1.3, 0.14], c)
		"nuke":
			ci.draw_circle(o, 0.18 * s, c)
			for i in 3:
				var a0: float = -PI * 0.5 + TAU * float(i) / 3.0 - PI / 6.0
				var q := PackedVector2Array()
				q.append(o + Vector2(cos(a0), sin(a0)) * 0.30 * s)
				for j in 7:
					var a: float = a0 + (PI / 3.0) * float(j) / 6.0
					q.append(o + Vector2(cos(a), sin(a)) * 0.95 * s)
				q.append(o + Vector2(cos(a0 + PI / 3.0), sin(a0 + PI / 3.0)) * 0.30 * s)
				ci.draw_colored_polygon(q, c)
		"head":
			ci.draw_arc(o, 0.62 * s, 0.0, TAU, 20, c, maxf(1.2, s * 0.16))
			ci.draw_line(o + Vector2(-0.95, 0) * s, o + Vector2(-0.35, 0) * s, c, maxf(1.2, s * 0.14))
			ci.draw_line(o + Vector2(0.35, 0) * s, o + Vector2(0.95, 0) * s, c, maxf(1.2, s * 0.14))
			ci.draw_line(o + Vector2(0, -0.95) * s, o + Vector2(0, -0.35) * s, c, maxf(1.2, s * 0.14))
			ci.draw_line(o + Vector2(0, 0.35) * s, o + Vector2(0, 0.95) * s, c, maxf(1.2, s * 0.14))
			ci.draw_circle(o, 0.14 * s, c)
		_:
			# a burst: whatever went off, it went off here
			var q2 := PackedVector2Array()
			for i in 16:
				var a2: float = TAU * float(i) / 16.0
				var r: float = (0.95 if i % 2 == 0 else 0.42) * s
				q2.append(o + Vector2(cos(a2), sin(a2)) * r)
			ci.draw_colored_polygon(q2, c)
