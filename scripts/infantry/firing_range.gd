class_name FiringRange
extends Node3D
## A range to try the small arms on. A firing line with every weapon laid out
## on the rack behind it -- F picks one up -- and a lane of boards out to three
## hundred metres. Each board keeps the holes it has been given and says how
## many, and where the last one went from the middle of it, so a group can be
## read without walking out to it. Nothing on it shoots back, and the ammunition
## does not run out.

const DISTANCES := [10.0, 25.0, 50.0, 100.0, 200.0, 300.0, 400.0, 600.0, 800.0, 1000.0]
## How far the boards are walked off the centre line, so that from the firing
## line no board is behind another: worked out by bearing, not by eye. With the
## far board on the centre line the rounds sent at it went into the top of the
## ten metre board in front of it. The long boards are walked out to the right
## in a fan of their own, each on a bearing nothing nearer is standing on.
const STAGGER := [-3.0, 3.0, -2.0, 4.0, -12.0, 10.0, 25.0, 45.0, 70.0, 90.0]
const LANE_LEN := 1015.0
## Slow motion while the bullet camera rides one of your rounds: how much of
## real time passes, as the choices Page Up and Page Down step through.
const SLOW_STEPS := [0.01, 0.02, 0.05, 0.1, 0.25]

var world: Node = null
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var targets: Array = []
var _rack: Dictionary = {}       # kit id -> the Drop on the rack, or null
var _rack_at: Dictionary = {}    # kit id -> where it lies
var _tick := 0.0

## Every round he has fired here that is still worth showing, newest last:
## {node, cal, kit, name, muzzle, v0, dir0, t, flown, pts, pos, vel, live,
##  hit, board}. The trace lines and the ballistics page are drawn from these.
var rounds: Array = []
const KEEP_ROUNDS := 16
var traces_on := true
var slow_i := 2
var _slowed := false
var _traces: MeshInstance3D
var _panel: Label
var _tips: Label
var _layer: CanvasLayer
var _dirty := false
## Where a range would go out from `centre`: the first bearing and distance
## from which a lane `LANE_LEN` long is clear at chest height all the way.
## Returns [origin, dir], or [] when nowhere round the town will do.
static func site_near(centre: Vector3) -> Array:
	var best: Array = []
	var best_score := -1.0
	for ring in range(0, 9):
		var r: float = 110.0 + float(ring) * 45.0
		for bi in 16:
			var a: float = TAU * float(bi) / 16.0 + float(ring) * 0.2
			var d := Vector3(cos(a), 0.0, sin(a))
			var p := centre + d * r
			p.y = Sim.height_at(p.x, p.z)
			# standing room at the firing line
			if Obstacles.hit(p + Vector3(0, 1.0, 0), 2.5) >= 0:
				continue
			var eye: Vector3 = p + Vector3(0, 1.5, 0)
			# the short lane straight down the middle, out to three hundred
			var far: Vector3 = p + d * 315.0
			far.y = Sim.height_at(far.x, far.z) + 1.2
			var look: Vector3 = (far - eye).normalized()
			var clear: float = Firearm.sight_range(eye, look, 335.0)
			var score: float = minf(clear, 315.0) / 315.0
			# and how many of the long boards can find somewhere to stand
			if clear >= 313.0:
				var right: Vector3 = d.cross(Vector3.UP).normalized()
				var taken: Array = []
				for i in DISTANCES.size():
					var dist: float = DISTANCES[i]
					if dist < 400.0:
						taken.append(atan2(float(STAGGER[i]), dist))
						continue
					var lat: float = _clear_lateral(p, d, eye, right, dist, float(STAGGER[i]), taken)
					if not is_nan(lat):
						taken.append(atan2(lat, dist))
						score += 1.0
			if score > best_score:
				best_score = score
				best = [p, d]
			if score >= 5.0:
				return [p, d]
	return best

func setup(owner_world: Node, at: Vector3, facing: Vector3) -> void:
	world = owner_world
	origin = at
	dir = Vector3(facing.x, 0.0, facing.z).normalized()

func _ready() -> void:
	top_level = true
	global_position = Vector3.ZERO
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	_firing_line(right)
	var bearings: Array = []
	var eye: Vector3 = origin + Vector3(0, 1.5, 0)
	for i in DISTANCES.size():
		var dist: float = DISTANCES[i]
		var lat: float = float(STAGGER[i])
		if dist >= 400.0:
			var found: float = _clear_lateral(origin, dir, eye, right, dist, lat, bearings)
			if not is_nan(found):
				lat = found
		bearings.append(atan2(lat, dist))
		var p: Vector3 = origin + dir * dist + right * lat
		p.y = Sim.height_at(p.x, p.z)
		var t := RangeTarget.new()
		t.distance = dist
		t.facing = -dir
		add_child(t)
		t.global_position = p
		targets.append(t)
	# the rack: every weapon there is, laid out behind the line
	var kits: Array = []
	for k in Firearm.KIT:
		kits.append(String(k["id"]))
	for i in kits.size():
		var along: float = (float(i) - float(kits.size() - 1) * 0.5) * 1.1
		var at: Vector3 = origin - dir * 3.0 + right * along
		_rack_at[kits[i]] = at
		_rack[kits[i]] = null
	_lay_rack()
	# the trace lines: every round's flight, as it flew
	_traces = MeshInstance3D.new()
	_traces.name = "Traces"
	_traces.mesh = ImmediateMesh.new()
	_traces.top_level = true
	_traces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.no_depth_test = false
	_traces.material_override = tm
	add_child(_traces)
	# the ballistics page, and the keys for it
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_panel = Label.new()
	# on the right, under the messages: the left is the key card and the map
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -500
	_panel.offset_right = -24
	_panel.offset_top = 250
	_panel.add_theme_font_size_override("font_size", 14)
	_panel.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	_panel.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_panel.add_theme_constant_override("outline_size", 5)
	_layer.add_child(_panel)
	_tips = Label.new()
	_tips.add_theme_font_size_override("font_size", 14)
	_tips.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_tips.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_tips.add_theme_constant_override("outline_size", 5)
	_tips.anchor_left = 0.5
	_tips.anchor_right = 0.5
	_tips.anchor_top = 1.0
	_tips.anchor_bottom = 1.0
	_tips.offset_left = -360
	_tips.offset_right = 360
	_tips.offset_top = -112
	_tips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer.add_child(_tips)
	Effects.round_log = _on_round
	Sim.report("FIRING RANGE — boards at 10, 25, 50, 100, 200, 300 m down the lane, and 400 to 1000 m out to the right", Sim.Ev.INFO)
	Sim.report("every weapon is on the rack behind the line: F to pick one up. The ammunition does not run out.",
		Sim.Ev.INFO)
	Sim.report("Y arms the slow-motion bullet camera; T trace lines; PgUp / PgDn slow-motion speed; BACKSPACE clears the boards",
		Sim.Ev.INFO)

## Where across the lane a long board can stand and still be seen from the
## line: the lane is surveyed clear down its middle only, and the long boards
## walked out to the side of it stood behind the edge of the town. The first
## offset, either side, with nothing in the way and no nearer board on the
## same bearing; the one asked for if none is.
static func _clear_lateral(at0: Vector3, fwd: Vector3, eye: Vector3, right: Vector3, dist: float,
		want: float, taken: Array) -> float:
	var tries: Array = [want]
	for k in range(1, 12):
		tries.append(want + float(k) * 12.0)
		tries.append(want - float(k) * 12.0)
	for lat in tries:
		var b: float = atan2(float(lat), dist)
		var clash := false
		for tb in taken:
			if absf(b - float(tb)) < deg_to_rad(0.6):
				clash = true
				break
		if clash:
			continue
		var at: Vector3 = at0 + fwd * dist + right * float(lat)
		at.y = Sim.height_at(at.x, at.z) + 1.5
		var to: Vector3 = at - eye
		if Firearm.sight_range(eye, to.normalized(), to.length()) >= to.length() - 2.0 \
				and _arc_clear(eye, at):
			return float(lat)
	return NAN

## Clear for the round, not just for the eye. A long shot is laid high for the
## drop and goes out over the line of sight in an arc -- two and a half metres
## over it at a thousand -- and a roof the line passed under took every round.
## Looked at as a slow rifle round would fly it, which is the highest arc.
static func _arc_clear(eye: Vector3, at: Vector3) -> bool:
	var dist: float = eye.distance_to(at)
	var tof: float = dist / 650.0
	var peak: float = 9.81 * tof * tof / 8.0 + 0.3
	var prev: Vector3 = eye
	var n: int = maxi(12, int(dist / 10.0))
	for k in range(1, n + 1):
		var f: float = float(k) / float(n)
		var q: Vector3 = eye.lerp(at, f) + Vector3.UP * (4.0 * peak * f * (1.0 - f))
		# the ground under the arc, with a little to spare for the low arc of
		# a fast round, which runs closer to the line of sight
		if q.y - 4.0 * peak * f * (1.0 - f) * 0.6 < Sim.height_at(q.x, q.z):
			return false
		if k % 4 == 0 or k == n:
			if Obstacles.segment(prev, q) < 1.0:
				return false
			prev = q
	return true

## The line itself: a painted stripe across the lane and a bench to rest on,
## and a stake every fifty metres down it so the distance can be read off.
func _firing_line(right: Vector3) -> void:
	var st := MeshKit.begin()
	var bs := Basis(right, Vector3.UP, -dir)
	var xf := Transform3D(bs, origin)
	# stripe
	MeshKit.box(st, Vector3(28.0, 0.03, 0.18), Vector3(0, 0.02, 0))
	var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.86, 0.80, 0.30), 0.9, 0.0)), "FiringLine")
	add_child(mi)
	mi.global_transform = xf
	mi.global_position.y = Sim.height_at(origin.x, origin.z)
	# a bench to rest on, off to the left of where he stands so it is not in
	# his way to the line
	var bst := MeshKit.begin()
	MeshKit.box(bst, Vector3(2.4, 0.06, 0.7), Vector3(-4.5, 0.88, -0.2))
	for sx in [-5.5, -3.5]:
		MeshKit.box(bst, Vector3(0.08, 0.86, 0.6), Vector3(sx, 0.43, -0.2))
	var bench := MeshKit.mi(MeshKit.finish(bst, MeshKit.mat(Color(0.42, 0.30, 0.18), 0.9, 0.0)), "Bench")
	add_child(bench)
	bench.global_transform = xf
	bench.global_position.y = Sim.height_at(origin.x, origin.z)
	for m in range(50, int(LANE_LEN), 50):
		if m > 300 and m % 100 != 0:
			continue
		for side in [-1.0, 1.0]:
			var p: Vector3 = origin + dir * float(m) + right * side * 15.0
			p.y = Sim.height_at(p.x, p.z)
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.1, 1.2, 0.1)
			post.mesh = bm
			post.material_override = MeshKit.mat(Color(0.9, 0.9, 0.85), 0.8, 0.0)
			add_child(post)
			post.global_position = p + Vector3(0, 0.6, 0)
			var lb := Label3D.new()
			lb.text = "%d m" % m
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.font_size = 64
			lb.pixel_size = 0.01
			lb.modulate = Color(1.0, 0.95, 0.6)
			add_child(lb)
			lb.global_position = p + Vector3(0, 1.6, 0)

func _lay_rack() -> void:
	for id in _rack:
		var d: Variant = _rack[id]
		if d != null and is_instance_valid(d):
			continue
		var at: Vector3 = _rack_at[id]
		var g: Dictionary = Firearm.spec(String(id))
		var drop := Firearm.Drop.new()
		drop.kit = String(id)
		drop.rounds = int(g["mag"])
		drop.life = 1e9
		world.add_child(drop)
		drop.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
		_rack[id] = drop

func _exit_tree() -> void:
	if Effects.round_log == Callable(self, "_on_round"):
		Effects.round_log = Callable()
	_slow(false)
	# the rack belongs to the range, not to the world it was laid out in
	for id in _rack:
		var d: Variant = _rack[id]
		if d != null and is_instance_valid(d):
			(d as Node).queue_free()
	_rack.clear()

# ------------------------------------------------------------ the rounds
## Every round fired anywhere comes past here first. His, from a gun, are
## marked with what they are and followed.
func _on_round(shot: Node3D, shooter: Node) -> void:
	var w: Variant = world.get("walker") if world != null else null
	if w == null or shooter != w or not (shot is Effects.Tracer):
		return
	var t := shot as Effects.Tracer
	if not t.small:
		return
	var wk: Walker = w
	var g: Dictionary = wk.gun_spec()
	var kit := String(g["id"])
	t.cal = Firearm.CAL.get(kit, {})
	var v0: Vector3 = t.vel
	rounds.append({"node": t, "cal": t.cal, "kit": kit, "name": String(g["name"]),
		"muzzle": t.global_position, "v0": v0.length(), "dir0": v0.normalized(),
		"drag": t.drag, "t": 0.0, "flown": 0.0, "pts": PackedVector3Array([t.global_position]),
		"pos": t.global_position, "vel": v0, "live": true, "hit": "", "board": null})
	while rounds.size() > KEEP_ROUNDS:
		rounds.pop_front()
	_dirty = true

## A board saying it was hit, and where on its face: put against the round
## that did it, which is the newest of his still in the air near it.
func board_hit(b: RangeTarget, at_cm: Vector2) -> void:
	# the one of his still flying that is nearest the board: it is within a
	# step of it, and nothing else of his can be
	var best: Dictionary = {}
	var bd := 80.0
	for r in rounds:
		if r["hit"] != "" or not bool(r["live"]):
			continue
		var d: float = (r["pos"] as Vector3).distance_to(b.global_position)
		if d < bd:
			bd = d
			best = r
	if not best.is_empty():
		best["hit"] = "%d m board, %s" % [int(b.distance), _offset_text(at_cm)]
		best["board"] = b

static func _offset_text(cm: Vector2) -> String:
	var lr := "%d cm %s" % [int(absf(cm.x)), "right" if cm.x > 0.0 else "left"] if absf(cm.x) >= 1.0 else "centre"
	var ud := "%d cm %s" % [int(absf(cm.y)), "high" if cm.y > 0.0 else "low"] if absf(cm.y) >= 1.0 else "level"
	return "%s, %s" % [lr, ud]

func _physics_process(delta: float) -> void:
	for r in rounds:
		if not bool(r["live"]):
			continue
		var n: Variant = r["node"]
		if n == null or not is_instance_valid(n):
			r["live"] = false
			_dirty = true
			continue
		var t := n as Effects.Tracer
		var p: Vector3 = t.global_position
		if t.ended_at != Vector3.INF:
			p = t.ended_at
		r["t"] = float(r["t"]) + delta
		r["flown"] = float(r["flown"]) + (r["pos"] as Vector3).distance_to(p)
		r["pos"] = p
		r["vel"] = t.vel
		var pts: PackedVector3Array = r["pts"]
		if pts.size() < 4000:
			pts.append(p)
			r["pts"] = pts
		_dirty = true

## Slow motion while the camera is on one of his rounds. The clock alone: the
## physics still ticks as often per second of the screen as ever, each tick a
## twentieth as long, so the round is stepped finely and drawn smoothly for no
## extra work. Raising the tick rate to match as well -- which this did -- ran
## the whole world twenty times over for every frame and put the round off its
## line.
func _slow(on: bool) -> void:
	if on:
		Engine.time_scale = float(SLOW_STEPS[slow_i])
	elif _slowed:
		Engine.time_scale = 1.0
	_slowed = on

func _ridden() -> Dictionary:
	var cam: Variant = world.get("cam") if world != null else null
	if cam == null or not is_instance_valid(cam):
		return {}
	var wc: Variant = (cam as Node).get("weapon_cam")
	if wc == null or not is_instance_valid(wc):
		return {}
	for r in rounds:
		if r["node"] == wc:
			return r
	return {}

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo or Sim.typing:
		return
	var k := (e as InputEventKey).physical_keycode
	match k:
		KEY_T:
			traces_on = not traces_on
			_dirty = true
			Sim.report("trace lines %s" % ("on" if traces_on else "off"), Sim.Ev.INFO)
		KEY_PAGEUP:
			slow_i = mini(slow_i + 1, SLOW_STEPS.size() - 1)
			Sim.report("slow motion x%s" % str(SLOW_STEPS[slow_i]), Sim.Ev.INFO)
		KEY_PAGEDOWN:
			slow_i = maxi(slow_i - 1, 0)
			Sim.report("slow motion x%s" % str(SLOW_STEPS[slow_i]), Sim.Ev.INFO)
		KEY_BACKSPACE:
			patch_all()
			rounds.clear()
			_dirty = true
			Sim.report("boards patched, traces cleared", Sim.Ev.INFO)
		_:
			return
	get_viewport().set_input_as_handled()

func _draw_traces() -> void:
	var im := _traces.mesh as ImmediateMesh
	im.clear_surfaces()
	_traces.global_transform = Transform3D.IDENTITY
	if not traces_on:
		return
	var any := false
	for r in rounds:
		var pts: PackedVector3Array = r["pts"]
		if pts.size() >= 2:
			any = true
			break
	if not any:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for r in rounds:
		var pts: PackedVector3Array = r["pts"]
		if pts.size() < 2:
			continue
		var o: Vector3 = r["muzzle"]
		var d0: Vector3 = r["dir0"]
		# coloured by what it has left: white at the muzzle, through amber, to
		# red as it slows to half
		var step: int = maxi(1, int(pts.size() / 600.0))
		var i := 0
		while i + step < pts.size():
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + step]
			var frac: float = clampf(a.distance_to(o) / maxf(o.distance_to(pts[pts.size() - 1]), 1.0), 0.0, 1.0)
			var c := Color(1.0, 1.0 - frac * 0.75, 1.0 - frac, 1.0)
			im.surface_set_color(c)
			im.surface_add_vertex(a)
			im.surface_set_color(c)
			im.surface_add_vertex(b)
			i += step
		# and the bore line it left the muzzle on, faint, to read the drop off
		var end: Vector3 = pts[pts.size() - 1]
		var along: float = (end - o).dot(d0)
		im.surface_set_color(Color(0.4, 0.8, 1.0, 1.0))
		im.surface_add_vertex(o)
		im.surface_set_color(Color(0.4, 0.8, 1.0, 1.0))
		im.surface_add_vertex(o + d0 * along)
		# and a tick down from the bore line to where it actually is
		im.surface_set_color(Color(0.4, 0.8, 1.0, 1.0))
		im.surface_add_vertex(o + d0 * along)
		im.surface_set_color(Color(0.4, 0.8, 1.0, 1.0))
		im.surface_add_vertex(end)
	im.surface_end()

## The ballistics page: the round being ridden, or the last one he fired.
func _draw_panel() -> void:
	var r: Dictionary = _ridden()
	if r.is_empty() and not rounds.is_empty():
		r = rounds[rounds.size() - 1]
	var slow_txt := ("SLOW x%s" % str(SLOW_STEPS[slow_i])) if _slowed else ""
	_tips.text = "Y  bullet camera (%s, slow motion)     T  trace lines (%s)     PgUp / PgDn  slow-mo speed x%s     BACKSPACE  clear boards" % [
		"armed" if bool(world.get("weapon_cam_on")) else "off", "on" if traces_on else "off",
		str(SLOW_STEPS[slow_i])]
	if r.is_empty():
		_panel.text = "BALLISTICS\nfire a round to see it here"
		return
	var cal: Dictionary = r["cal"]
	var m: float = Firearm.mass_of(String(r["kit"]))
	var v0: float = float(r["v0"])
	var vel: Vector3 = r["vel"]
	var v: float = vel.length()
	var o: Vector3 = r["muzzle"]
	var d0: Vector3 = r["dir0"]
	var pos: Vector3 = r["pos"]
	var rel: Vector3 = pos - o
	var along: float = rel.dot(d0)
	# drop below the bore line, and drift across it, in the bore's own frame
	var off: Vector3 = rel - d0 * along
	var upv: Vector3 = (Vector3.UP - d0 * d0.dot(Vector3.UP)).normalized()
	var across: Vector3 = d0.cross(Vector3.UP).normalized()
	var drop: float = -off.dot(upv)
	var drift: float = off.dot(across)
	var e0: float = 0.5 * m * v0 * v0
	var e: float = 0.5 * m * v * v
	var mach: float = v / 343.0
	var lines: Array = [
		"BALLISTICS%s" % (("    " + slow_txt) if slow_txt != "" else ""),
		"%s  —  %s" % [String(r["name"]), String(cal.get("name", "?"))],
		"bullet          %.1f mm, %.0f gr (%.1f g)" % [float(cal.get("d", 0.0)) * 1000.0, float(cal.get("gr", 0.0)), m * 1000.0],
		"drag figure     %.4f /m at sea level" % float(r["drag"]),
		"muzzle          %.0f m/s   %.0f J" % [v0, e0],
		"now             %.0f m/s   Mach %.2f   %.0f J  (%.0f%% of its energy)" % [v, mach, e, 100.0 * e / maxf(e0, 1.0)],
		"time of flight  %.3f s" % float(r["t"]),
		"range           %.1f m flown, %.1f m from the muzzle" % [float(r["flown"]), rel.length()],
		"drop            %.1f cm below the bore line" % (drop * 100.0),
		"drift           %.1f cm %s" % [absf(drift) * 100.0, "right" if drift >= 0.0 else "left"],
		"angle           %+.2f deg below the bore" % rad_to_deg(atan2(-vel.normalized().dot(upv), vel.normalized().dot(d0))),
	]
	if String(r["hit"]) != "":
		lines.append("hit             %s" % String(r["hit"]))
	elif not bool(r["live"]):
		lines.append("stopped         %.0f m out, no board" % rel.length())
	else:
		lines.append("in flight")
	_panel.text = "\n".join(PackedStringArray(lines))

func _process(delta: float) -> void:
	# slow motion while the camera is on one of his rounds, and the round
	# drawn as itself, to its calibre, for the lens to look at
	var ridden := _ridden()
	if not ridden.is_empty():
		var rn: Variant = ridden["node"]
		if is_instance_valid(rn):
			(rn as Effects.Tracer).show_round(true)
	var cam: Variant = world.get("cam") if world != null else null
	var riding: bool = cam != null and is_instance_valid(cam) and (cam as Node).call("riding") \
		and (not ridden.is_empty() or _slowed)
	_slow(riding)
	if _dirty:
		_dirty = false
		_draw_traces()
	_draw_panel()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	# whatever was taken off the rack goes back on it
	_lay_rack()
	# and the man on the line never runs dry
	var w: Variant = world.get("walker") if world != null else null
	if w != null and is_instance_valid(w):
		var wk: Walker = w
		var g: Dictionary = wk.gun_spec()
		var full: int = int(g["mag"]) * maxi(int(g.get("spare", 3)), 3)
		if wk.spare < full:
			wk.spare = full
			if wk.kit_idx < wk._spare.size():
				wk._spare[wk.kit_idx] = full
		wk.grenades = maxi(wk.grenades, 2)

## Clear the holes off every board.
func patch_all() -> void:
	for t in targets:
		if is_instance_valid(t):
			(t as RangeTarget).patch()


## One board on a post, facing the line: a man-sized card with the rings on
## it. It takes rounds the way a man does -- through the same test, from the
## round's own path -- and keeps a mark where each one went in.
class RangeTarget extends Node3D:
	## The card, and how high its middle stands: bigger the further out, so a
	## thousand metre board is something a scope can find.
	var bw := 0.60
	var bh := 1.00
	var cy := 1.25
	const MAX_HOLES := 60
	var distance := 0.0
	var facing := Vector3.BACK
	var team := 1
	var hits := 0
	var _holes: Array = []
	var _label: Label3D
	var _hole_mesh: Mesh
	var _flash := 0.0
	var _card: MeshInstance3D
	var _card_mat: StandardMaterial3D

	func _ready() -> void:
		if distance >= 800.0:
			bw = 1.6
			bh = 2.4
			cy = 1.8
		elif distance >= 400.0:
			bw = 1.0
			bh = 1.6
			cy = 1.5
		add_to_group("hittable")
		add_to_group("range_target")
		look_at(global_position + facing, Vector3.UP)
		# the card faces local +Z, toward the line
		rotate_object_local(Vector3.UP, PI)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.08, cy - bh * 0.5 + 0.05, 0.08)
		post.mesh = pm
		post.material_override = MeshKit.mat(Color(0.35, 0.27, 0.18), 0.9, 0.0)
		post.position = Vector3(0, (cy - bh * 0.5) * 0.5, -0.06)
		add_child(post)
		_card = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(bw, bh)
		_card.mesh = qm
		_card_mat = StandardMaterial3D.new()
		_card_mat.albedo_texture = _face()
		_card_mat.roughness = 0.95
		_card.material_override = _card_mat
		_card.position = Vector3(0, cy, 0)
		add_child(_card)
		var back := MeshInstance3D.new()
		var bq := QuadMesh.new()
		bq.size = Vector2(bw, bh)
		back.mesh = bq
		back.material_override = MeshKit.mat(Color(0.55, 0.45, 0.30), 0.95, 0.0)
		back.position = Vector3(0, cy, -0.01)
		back.rotation = Vector3(0, PI, 0)
		add_child(back)
		var hm := QuadMesh.new()
		hm.size = Vector2(0.022, 0.022)
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.05, 0.05, 0.05)
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.material = hmat
		_hole_mesh = hm
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 48
		_label.pixel_size = 0.004 * clampf(distance / 25.0, 1.0, 9.0)
		_label.outline_size = 8
		_label.position = Vector3(0, cy + bh * 0.5 + 0.25 * clampf(distance / 25.0, 1.0, 9.0), 0)
		add_child(_label)
		_say("")

	## The rings, drawn once and shared.
	static var _tex: ImageTexture = null
	static func _face() -> ImageTexture:
		if _tex != null:
			return _tex
		var w := 120
		var h := 200
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		img.fill(Color(0.93, 0.91, 0.84))
		var c := Vector2(w * 0.5, h * 0.5)
		for y in h:
			for x in w:
				var d: float = Vector2(x, y).distance_to(c) / (w * 0.5)
				var col := Color(0.93, 0.91, 0.84)
				if d < 0.25:
					col = Color(0.75, 0.12, 0.10)
				elif d < 0.5:
					col = Color(0.12, 0.12, 0.12) if int(d * 20.0) % 2 == 0 else Color(0.93, 0.91, 0.84)
				elif d < 1.0 and int(d * 10.0) % 2 == 0:
					col = Color(0.20, 0.20, 0.20)
				img.set_pixel(x, y, col)
		_tex = ImageTexture.create_from_image(img)
		return _tex

	func is_alive() -> bool:
		return true

	func hit_radius() -> float:
		return 0.6

	## Where a round's path from `a` to `b` crosses the card: how hard (2 in
	## the red, 1 on the card, 0 a miss) and how far along the path. The same
	## question a soldier is asked, so a target is hit exactly when a man
	## standing there would have been.
	func bullet_hit(a: Vector3, b: Vector3) -> Vector2:
		var inv := _card.global_transform.affine_inverse()
		var la: Vector3 = inv * a
		var lb: Vector3 = inv * b
		if (la.z > 0.0) == (lb.z > 0.0) or absf(lb.z - la.z) < 1e-6:
			return Vector2.ZERO
		var t: float = la.z / (la.z - lb.z)
		var p: Vector3 = la.lerp(lb, t)
		if absf(p.x) > bw * 0.5 or absf(p.y) > bh * 0.5:
			return Vector2.ZERO
		_mark(p)
		return Vector2(2.0 if Vector2(p.x, p.y).length() < bw * 0.125 else 1.0, t)

	func take_hit(_amount: float, _from: Node = null) -> void:
		_flash = 0.25

	func _mark(p: Vector3) -> void:
		hits += 1
		var hole := MeshInstance3D.new()
		hole.mesh = _hole_mesh
		hole.position = Vector3(p.x, p.y, 0.004)
		_card.add_child(hole)
		_holes.append(hole)
		while _holes.size() > MAX_HOLES:
			var old: Node = _holes.pop_front()
			if is_instance_valid(old):
				old.queue_free()
		var cm := Vector2(p.x, p.y) * 100.0
		var lr := "%d cm %s" % [int(absf(cm.x)), "right" if cm.x > 0.0 else "left"] if absf(cm.x) >= 1.0 else "centre"
		var ud := "%d cm %s" % [int(absf(cm.y)), "high" if cm.y > 0.0 else "low"] if absf(cm.y) >= 1.0 else "level"
		_say("last: %s, %s" % [lr, ud])
		var fr: Node = get_parent()
		if fr != null and fr.has_method("board_hit"):
			fr.call("board_hit", self, cm)

	func patch() -> void:
		for h in _holes:
			if is_instance_valid(h):
				(h as Node).queue_free()
		_holes.clear()
		hits = 0
		_say("")

	func _say(last: String) -> void:
		_label.text = "%d m   %d hit%s%s" % [int(distance), hits, "" if hits == 1 else "s",
			("\n" + last) if last != "" else ""]

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash -= delta
			_card_mat.albedo_color = Color(1.0, 0.85, 0.6) if _flash > 0.0 else Color.WHITE
