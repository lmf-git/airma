class_name MapView
extends Control
## Tactical map on M. The background is baked once from the same height and
## biome fields the terrain uses, with hill shading; everything else is drawn
## live on top.

const RES := 192
const HALF := 20000.0          # metres covered by the baked image, each way

var jet: Node = null
var world: Node = null
var tank: Node = null          # set while driving, enables map fire missions
var zoom := 1.0
var centre := Vector2.ZERO     # world metres
var follow := true
var _tex: ImageTexture
var _font: Font
var _drag := false
var _mouse_was := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)

## Shaded relief over biome colour, sampled straight from the world fields.
func bake() -> void:
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var step := HALF * 2.0 / float(RES)
	for j in RES:
		var z := -HALF + float(j) * step
		for i in RES:
			var x := -HALF + float(i) * step
			var h := Sim.height_at(x, z)
			var c: Color
			if h < Sim.WATER_LEVEL:
				c = Color(0.06, 0.16, 0.26).lerp(Color(0.10, 0.24, 0.34),
					clampf((h + 400.0) / 400.0, 0.0, 1.0))
			else:
				c = Sim.biome_colour(x, z, h, 1.0)
				# hill shade from the local gradient, sun from the north west
				var dx := Sim.height_at(x + step, z) - h
				var dz := Sim.height_at(x, z + step) - h
				var shade: float = clampf(0.72 + (-dx - dz) / (step * 0.55), 0.35, 1.5)
				c = Color(c.r * shade, c.g * shade, c.b * shade)
				if Sim.road_distance(x, z) < step * 0.8:
					c = c.lerp(Color(0.14, 0.14, 0.15), 0.75)
			img.set_pixel(i, j, c)
	_tex = ImageTexture.create_from_image(img)

func toggle() -> void:
	visible = not visible
	set_process(visible)
	# the map is useless without a pointer, and driving or walking captures it
	if visible:
		_mouse_was = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if jet != null and is_instance_valid(jet):
			follow = true
	else:
		Input.mouse_mode = _mouse_was
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampf(zoom * 1.25, 0.35, 14.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampf(zoom / 1.25, 0.35, 14.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# right click lays a fire mission for an artillery piece
			if tank != null and is_instance_valid(tank) and tank.is_indirect():
				var vp := get_viewport_rect().size
				var org := vp * 0.5
				var scl := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
				var w := centre + (mb.position - org) / scl
				tank.map_target = Vector3(w.x, Sim.height_at(w.x, w.y), w.y)
				Sim.report("fire mission: %.1f km" % (
					tank.global_position.distance_to(tank.map_target) * 0.001), Sim.Ev.INFO)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			if mb.pressed:
				follow = false
	elif e is InputEventMouseMotion and _drag:
		var vp := get_viewport_rect().size
		var px_per_m := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
		centre -= (e as InputEventMouseMotion).relative / px_per_m

func _process(_d: float) -> void:
	if follow and jet != null and is_instance_valid(jet):
		centre = Vector2(jet.global_position.x, jet.global_position.z)
	queue_redraw()

func _w2s(p: Vector2, org: Vector2, px_per_m: float) -> Vector2:
	return org + (p - centre) * px_per_m

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.03, 0.04, 0.93), true)
	var org := vp * 0.5
	var ppm := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
	if _tex:
		var span := Vector2(HALF * 2.0, HALF * 2.0) * ppm
		draw_texture_rect(_tex, Rect2(_w2s(Vector2(-HALF, -HALF), org, ppm), span), false)

	# runway
	var rw := Sim.RUNWAY_LEN * 0.5
	draw_line(_w2s(Vector2(0, -rw), org, ppm), _w2s(Vector2(0, rw), org, ppm),
		Color(0.95, 0.95, 0.95), maxf(2.0, Sim.RUNWAY_HALF_W * 2.0 * ppm))
	_label(_w2s(Vector2(0, rw + 400.0), org, ppm), "RWY 18/36", Color(0.9, 0.95, 1.0))

	# trunk roads over the top so the network reads at any zoom
	for r in Sim.ROADS:
		draw_line(_w2s(r[0], org, ppm), _w2s(r[1], org, ppm), Color(0.55, 0.5, 0.42, 0.8), 1.6)

	# towns
	for t in Scenery.TOWNS:
		var c: Vector3 = t[0]
		var p := _w2s(Vector2(c.x, c.z), org, ppm)
		draw_arc(p, maxf(float(t[1]) * ppm, 3.0), 0, TAU, 24, Color(0.75, 0.72, 0.6, 0.7), 1.2)
		_label(p + Vector2(6, -6), str(t[4]), Color(0.85, 0.85, 0.8))

	# carrier
	if world and is_instance_valid(world.get("carrier")):
		var cp: Vector3 = world.carrier.global_position
		var p := _w2s(Vector2(cp.x, cp.z), org, ppm)
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(0.6, 0.8, 1.0), false, 1.6)
		_label(p + Vector2(9, 4), "CVN", Color(0.6, 0.8, 1.0))

	# objectives
	for z in get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		var p := _w2s(Vector2(z.global_position.x, z.global_position.z), org, ppm)
		var col := Color(0.8, 0.8, 0.82)
		if z.owner_team == 0:
			col = Color(0.35, 0.75, 1.0)
		elif z.owner_team == 1:
			col = Color(1.0, 0.35, 0.3)
		draw_arc(p, maxf(z.radius * ppm, 6.0), 0, TAU, 28, col, 1.8)
		_label(p - Vector2(4, 8), str(z.label), col)

	# contacts
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == jet:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var hostile: bool = ("team" in n) and n.team != 0
		var p := _w2s(Vector2(n.global_position.x, n.global_position.z), org, ppm)
		var col := Color(1.0, 0.35, 0.3) if hostile else Color(0.4, 0.85, 1.0)
		if n is GroundTarget or n is Tank:
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), col, true)
		else:
			draw_circle(p, 3.0, col)

	# own aircraft, with its heading
	if jet != null and is_instance_valid(jet):
		var p := _w2s(Vector2(jet.global_position.x, jet.global_position.z), org, ppm)
		var fwd: Vector3 = -jet.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 11.0, p - dir * 6.0 + side * 6.0,
			p - dir * 6.0 - side * 6.0]), Color(0.4, 1.0, 0.5))
		_label(Vector2(24, vp.y - 96), "POS  %+.1f km E   %+.1f km N   ALT %d ft" % [
			jet.global_position.x * 0.001, -jet.global_position.z * 0.001,
			int(jet.global_position.y * 3.28084)], Color(0.7, 1.0, 0.8))

	# artillery fire mission marker
	if tank != null and is_instance_valid(tank) and tank.is_indirect():
		var tp := _w2s(Vector2(tank.global_position.x, tank.global_position.z), org, ppm)
		draw_rect(Rect2(tp - Vector2(4, 4), Vector2(8, 8)), Color(0.4, 1.0, 0.5), false, 2.0)
		if tank.map_target != Vector3.INF:
			var mp := _w2s(Vector2(tank.map_target.x, tank.map_target.z), org, ppm)
			draw_line(mp - Vector2(10, 10), mp + Vector2(10, 10), Color(1.0, 0.5, 0.2), 2.0)
			draw_line(mp - Vector2(10, -10), mp + Vector2(10, -10), Color(1.0, 0.5, 0.2), 2.0)
			draw_arc(mp, 14.0, 0, TAU, 20, Color(1.0, 0.5, 0.2), 1.5)
			draw_line(tp, mp, Color(1.0, 0.5, 0.2, 0.5), 1.2)
			_label(mp + Vector2(18, 4), "%.1f km" % (
				tank.global_position.distance_to(tank.map_target) * 0.001),
				Color(1.0, 0.6, 0.3))
		_label(Vector2(24, vp.y - 120), "right click to lay a fire mission",
			Color(1.0, 0.7, 0.4), 14)

	# scale bar and legend
	var bar_m := 10000.0
	while bar_m * ppm > minf(vp.x, vp.y) * 0.3:
		bar_m *= 0.5
	var bx := vp.x - 40.0 - bar_m * ppm
	draw_line(Vector2(bx, vp.y - 54), Vector2(bx + bar_m * ppm, vp.y - 54),
		Color(0.9, 0.95, 1.0), 2.0)
	_label(Vector2(bx, vp.y - 60), "%d km" % int(bar_m * 0.001), Color(0.9, 0.95, 1.0))
	_label(Vector2(24, 40), "TACTICAL MAP", Color(0.6, 0.95, 1.0), 22)
	_label(Vector2(24, 64), "wheel zoom   drag to pan   M to close", Color(0.6, 0.7, 0.8), 14)
	# north arrow
	var na := Vector2(vp.x - 60.0, 70.0)
	draw_line(na + Vector2(0, 18), na - Vector2(0, 18), Color(0.9, 0.95, 1.0), 2.0)
	draw_colored_polygon(PackedVector2Array([na - Vector2(0, 22), na + Vector2(-6, -10),
		na + Vector2(6, -10)]), Color(0.9, 0.95, 1.0))
	_label(na + Vector2(-5, 36), "N", Color(0.9, 0.95, 1.0))

func _label(at: Vector2, t: String, col: Color, pt := 13) -> void:
	draw_string(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, pt, col)
