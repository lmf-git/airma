class_name MapView
extends Control
## Tactical map on M. The background is baked once from the same height and
## biome fields the terrain uses, with hill shading; everything else is drawn
## live on top.

## The relief image. It covered twenty kilometres each way while the world is
## seventy and the terrain reaches ninety-two — so the map drew a small square
## of ground in the middle of a great deal of nothing, which is exactly what one
## chunk looks like. It now covers the whole world, and at enough resolution
## that the extra ground is worth having.
const RES := 512
const HALF := 600000.0         # metres covered by the baked image, each way

## And a second sheet over the ground you are on.
##
## One image cannot serve both ends of the zoom. The world sheet is 2344 m to
## the texel, which is right for looking at a continent and useless for looking
## at ground: the map opens framing about forty kilometres, and forty kilometres
## of a 512-pixel world sheet is *twenty-one texels* across the screen -- one
## smear of colour, which is exactly what it looked like. Enough resolution to
## fix that in the world sheet would be a 12500-pixel image and 469 MB.
##
## So there are two, the same arrangement the ground mask already uses: the
## world at 2344 m a texel, and the ground under the chart at 117 m, drawn over
## the top of it.
## Past the edge of the detail sheet the world sheet is what is left, which is
## also the point at which a texel of it is smaller than a pixel.
const DETAIL_RES := 2048
const DETAIL_HALF := 120000.0

var aircraft: Node = null
var world: Node = null
var tank: Node = null          # set while driving, enables map fire missions
var ship: Node = null          # set while crewing, enables strategic aiming
## Where the strategic round has been sent, or INF.
var strategic_mark := Vector3.INF
## Which satellite the ASAT launchers have been told to shoot at. Picked with
## shift and click on the map, because there is nowhere else you can see one.
var sat_target: Node = null

## What the map is holding as an aiming point. `_strategic_strike` asks for this.
func target_point() -> Vector3:
	return strategic_mark
## Zoom one used to frame forty kilometres; the same view of the same ground is
## now a little over three, so the map does not open showing the whole planet.
## Opens framing about forty kilometres, which is the ground you actually fly
## over; the rest of the six hundred is there to be zoomed out to.
var zoom := 29.0
var centre := Vector2.ZERO     # world metres
var follow := true
var _tex: ImageTexture
## The ground under the chart at sixteen times the resolution, over the world
## sheet. It follows the chart, because the chart follows the player.
var _detail_tex: ImageTexture
var _font: Font
var _drag := false
var _mouse_was := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	# The map is the planet whenever the world is one.
	globe = Sim.globe
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)

## Shaded relief over biome colour, rasterised from the world fields and kept
## on disk, so only the very first launch after a change to the world pays for
## it.
var map_stats := {}

func bake() -> void:
	var t0 := Time.get_ticks_msec()
	var buf: PackedByteArray
	var cached: Variant = WorldBake.get_baked("map_relief")
	if cached is PackedByteArray and (cached as PackedByteArray).size() == RES * RES * 3:
		buf = cached
	else:
		# The whole picture in one call: relief, hill shade, biome colour and
		# the road network. Every one of a quarter of a million pixels wants
		# three heights, a biome and a distance to the nearest road, and asking
		# for them a point at a time from eight row workers meant a million and
		# a half crossings of the extension boundary with all eight queueing at
		# it. It is the same arithmetic; it is simply done where the fields are.
		buf = Sim.native.map_relief(RES, HALF)
		WorldBake.put("map_relief", buf)
	var img := Image.create_from_data(RES, RES, false, Image.FORMAT_RGB8, buf)
	_tex = ImageTexture.create_from_image(img)
	var land := 0
	var sea := 0
	for k2 in range(0, buf.size(), 3):
		if buf[k2 + 2] > buf[k2 + 1]:
			sea += 1
		else:
			land += 1
	_detail_tex = _bake_sheet("map_detail", DETAIL_RES, DETAIL_HALF)
	map_stats = {"res": RES, "ms": Time.get_ticks_msec() - t0, "land": land,
		"sea": sea, "detail_res": DETAIL_RES, "detail_half": DETAIL_HALF,
		"world_m_per_texel": HALF * 2.0 / float(RES),
		"detail_m_per_texel": DETAIL_HALF * 2.0 / float(DETAIL_RES)}

## The baked relief, for anything else that wants to draw the same ground -- the
## planet body is painted with it.
func relief() -> ImageTexture:
	return _tex

## One sheet of relief, baked once and kept. Both sheets come off the same
## rasteriser and differ only in how much ground they cover.
func _bake_sheet(key: String, n: int, half: float) -> ImageTexture:
	var buf: PackedByteArray
	# On the planet the close-in sheet is the ground under the *chart*, and the
	# chart moves with the player -- so it is neither the same picture as last
	# time nor worth keeping on disk. Baked fresh, and re-baked when the chart
	# is put somewhere else.
	# Both sheets, on the planet. The world sheet used to be rasterised from the
	# flat field even in globe mode, so the tactical chart drew one world and
	# the globe drew another -- which is exactly what it looked like.
	if Sim.globe:
		buf = Sim.native.map_relief_globe(n, half)
	else:
		var cached: Variant = WorldBake.get_baked(key)
		if cached is PackedByteArray \
				and (cached as PackedByteArray).size() == n * n * 3:
			buf = cached
		else:
			buf = Sim.native.map_relief(n, half)
			WorldBake.put(key, buf)
	return ImageTexture.create_from_image(
		Image.create_from_data(n, n, false, Image.FORMAT_RGB8, buf))

## The chart has moved: the close-in sheet is of somewhere else now.
func rechart() -> void:
	if not Sim.globe:
		return
	_detail_tex = _bake_sheet("map_detail", DETAIL_RES, DETAIL_HALF)
	queue_redraw()

## The close-in sheet, for anything that wants the ground under the chart.
func detail() -> ImageTexture:
	return _detail_tex

func toggle() -> void:
	visible = not visible
	set_process(visible)
	# The camera must not take the mouse off the map: freelook shares CMD with
	# the objective marker.
	Sim.ui_pointer = visible
	# the map is useless without a pointer, and driving or walking captures it
	if visible:
		_mouse_was = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _me() != null:
			follow = true
	else:
		Input.mouse_mode = _mouse_was
	queue_redraw()

## What is on the map, and why.
##
## The map drew the ground and the objectives and nothing that moves, so it was
## a survey chart rather than a tactical picture. Now it shows contacts -- but
## only the ones somebody on your side can actually account for: your own units
## always, and a hostile only while one of yours can see it or is holding it on
## radar. Everything else is not on the map because nobody knows it is there.
const DETECT_EVERY := 0.6
var _contacts: Array = []
var _contact_t := 0.0

func _refresh_contacts() -> void:
	_contacts = []
	var mine: Array = []
	var theirs: Array = []
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n.is_in_group("no_lock") or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		# Ours, theirs, and everybody else. Neutral traffic is not something you
		# have to *find* -- a container ship broadcasts who and where it is --
		# so treating it as an enemy contact meant it only appeared when one of
		# your own units happened to be within sight of it, and the rest of the
		# time there was nothing on the map to lock on to.
		var side: int = int(n.team) if ("team" in n) else 0
		if side == 0:
			mine.append(n)
		elif side == 1:
			theirs.append(n)
		else:
			_contacts.append({"n": n, "hostile": false, "neutral": true})
	for f in mine:
		_contacts.append({"n": f, "hostile": false, "neutral": false})
	for h in theirs:
		var p: Vector3 = (h as Node3D).global_position
		var seen := false
		for f2 in mine:
			var fp: Vector3 = (f2 as Node3D).global_position
			var d: float = fp.distance_to(p)
			# an aeroplane carries a radar; anything else has to be able to see it
			# The side's whole picture, not just this airframe's own set: a
			# satellite or an early warning aircraft widens what the map shows,
			# which is most of the reason for having either.
			var reach: float = maxf(Sim.coverage(
				int(f2.team) if ("team" in f2) else 0), 26000.0) if f2 is Aircraft \
				else 14000.0
			if d > reach:
				continue
			if d > 1800.0 and not Sim.line_of_sight(fp + Vector3(0, 6, 0),
					p + Vector3(0, 6, 0), 250.0):
				continue
			seen = true
			break
		if seen:
			_contacts.append({"n": h, "hostile": true, "neutral": false})

## The contact nearest a point on screen, if the click is close enough to mean it.
func _contact_near(at: Vector2, org: Vector2, ppm: float) -> Node:
	var best: Node = null
	var bd := 18.0
	for c in _contacts:
		# Checked before it is typed. The list is rebuilt on a timer, so
		# anything shot down between two ticks is still in it -- and assigning a
		# freed instance to a typed variable is itself the error, before any
		# validity check gets a chance to run.
		var nv: Variant = c["n"]
		if not is_instance_valid(nv):
			continue
		var n: Node3D = nv
		var p: Vector3 = (n as Node3D).global_position
		var d: float = _w2s(Vector2(p.x, p.z), org, ppm).distance_to(at)
		if d < bd:
			bd = d
			best = n
	return best

func _gui_input(e: InputEvent) -> void:
	# The globe is a view, not a chart: it turns and zooms, and the fire
	# missions and aiming points stay on the chart where the ground is flat and
	# a click means a coordinate. The one thing it does take is a satellite,
	# because seeing where one actually is over the planet is the reason to be
	# looking at a planet.
	if globe:
		# A trackpad does not send wheel buttons. Two fingers on a Mac trackpad
		# is a pan gesture and a pinch is a magnify, and with neither handled
		# the map simply could not be zoomed on a laptop.
		if e is InputEventPanGesture:
			globe_zoom = clampf(globe_zoom * pow(1.08,
				-(e as InputEventPanGesture).delta.y), 0.6, 260.0)
			queue_redraw()
			return
		if e is InputEventMagnifyGesture:
			globe_zoom = clampf(
				globe_zoom * (e as InputEventMagnifyGesture).factor, 0.6, 260.0)
			queue_redraw()
			return
		if e is InputEventMouseButton:
			var gb := e as InputEventMouseButton
			if gb.button_index == MOUSE_BUTTON_WHEEL_UP and gb.pressed:
				globe_zoom = clampf(globe_zoom * 1.2, 0.6, 260.0)
			elif gb.button_index == MOUSE_BUTTON_WHEEL_DOWN and gb.pressed:
				globe_zoom = clampf(globe_zoom / 1.2, 0.6, 260.0)
			elif gb.button_index == MOUSE_BUTTON_RIGHT and gb.pressed:
				_pick_satellite_globe(gb.position)
			elif gb.button_index == MOUSE_BUTTON_LEFT:
				_drag = gb.pressed
		elif e is InputEventMouseMotion and _drag:
			var rel := (e as InputEventMouseMotion).relative
			# Slower the closer in you are, or a zoomed globe spins away under
			# the pointer.
			var g: float = 0.006 / maxf(sqrt(globe_zoom), 1.0)
			globe_spin = wrapf(globe_spin - rel.x * g, -PI, PI)
			globe_tilt = clampf(globe_tilt - rel.y * g, -PI * 0.49, PI * 0.49)
		return
	# The chart, the same way: pan to zoom, pinch to zoom.
	if e is InputEventPanGesture:
		zoom = clampf(zoom * pow(1.10,
			-(e as InputEventPanGesture).delta.y), 1.0, 400.0)
		follow = false
		queue_redraw()
		return
	if e is InputEventMagnifyGesture:
		zoom = clampf(zoom * (e as InputEventMagnifyGesture).factor, 1.0, 400.0)
		queue_redraw()
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampf(zoom * 1.25, 1.0, 400.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampf(zoom / 1.25, 1.0, 400.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# On a satellite, either button assigns it. Nothing else on the map
			# lives a hundred kilometres up, so there is nothing for a right
			# click up there to be confused with — and reaching for right click
			# is what anybody does when they want to target something.
			if _pick_satellite(mb.position):
				return
			# right click lays a fire mission for an artillery piece, and the
			# aiming point for a strategic launch when you are in the boat that
			# carries one. There was no path at all for the latter: the map
			# only ever spoke to a tank, and `_strategic_strike` asked the map
			# for a `target_point` it did not have — so aiming the round on the
			# map silently did nothing and the only way to send it was the pod.
			var vp := get_viewport_rect().size
			var org := vp * 0.5
			var scl := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
			# On the globe the click is unprojected through the ball; on the
			# chart it is a straight scale. Everything after this is the same
			# either way, which is the point of doing it here.
			var w: Vector2 = _globe_point(mb.position) if globe \
				else centre + (mb.position - org) / scl
			if is_inf(w.x):
				return
			var at := Vector3(w.x, Sim.height_at(w.x, w.y), w.y)
			# Clicked on something rather than somewhere? Then it is a lock, and
			# the round guides onto the unit instead of onto the patch of ground
			# the unit happened to be standing on when you pressed the button.
			var hit: Node = _contact_near_globe(mb.position) if globe \
				else _contact_near(mb.position, org, scl)
			if tank != null and is_instance_valid(tank) and tank.is_indirect():
				# Shift adds a point rather than replacing one. A round that
				# carries several warheads can be given several marks -- which
				# is what "independently targetable" means -- and each warhead
				# takes one as the bus opens. Without shift it is the primary
				# mark and the extra ones are forgotten.
				if mb.shift_pressed:
					var extra: Vector3 = (hit as Node3D).global_position \
						if hit != null else at
					tank.mirv_marks.append(extra)
					Sim.report("warhead %d assigned: %.1f km" % [
						tank.mirv_marks.size(),
						tank.global_position.distance_to(extra) * 0.001],
						Sim.Ev.INFO)
					return
				tank.mirv_marks.clear()
				tank.map_lock = hit
				tank.map_target = (hit as Node3D).global_position if hit != null else at
				if hit != null:
					Sim.report("locked: %s at %.1f km" % [
						String(hit.call("display_name")) if hit.has_method("display_name")
						else String(hit.name),
						tank.global_position.distance_to(tank.map_target) * 0.001],
						Sim.Ev.GOOD)
					return
				Sim.report("fire mission: %.1f km" % (
					tank.global_position.distance_to(tank.map_target) * 0.001), Sim.Ev.INFO)
			elif ship != null and is_instance_valid(ship) and ship.can_launch():
				strategic_mark = at
				ship.strategic_aim = at
				Sim.report("aiming point set: %.0f km" % (
					ship.global_position.distance_to(at) * 0.001), Sim.Ev.INFO)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# CTRL and click plants an objective marker, and CTRL and click on a
			# satellite assigns it to the ASAT launchers. Deliberately not
			# shift: shift already belongs to the weapons — it is what assigns
			# a warhead on a MIRV bus and picks the extra aiming points for a
			# cluster round — and putting a navigation marker on the same
			# modifier meant reaching for one and getting the other.
			if (mb.ctrl_pressed or mb.meta_pressed) and mb.pressed:
				if _pick_satellite(mb.position):
					return
				var vp0 := get_viewport_rect().size
				var ppm0 := minf(vp0.x, vp0.y) * 0.86 * zoom / (HALF * 2.0)
				var org0 := vp0 * 0.5
				var w := centre + (mb.position - org0) / ppm0
				var at := Vector3(w.x, Sim.height_at(w.x, w.y), w.y)
				if Sim.objective != Vector3.INF \
						and Vector2(Sim.objective.x - at.x,
							Sim.objective.z - at.z).length() < 40.0 / ppm0 * 12.0:
					Sim.clear_objective()
				else:
					Sim.set_objective(at)
				return
			_drag = mb.pressed
			if mb.pressed:
				follow = false
	elif e is InputEventMouseMotion and _drag:
		var vp := get_viewport_rect().size
		var px_per_m := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
		centre -= (e as InputEventMouseMotion).relative / px_per_m

func _process(d: float) -> void:
	# A bake finishing is the one thing that changes the picture without
	# anything on screen having moved, so it is collected here rather than only
	# where the globe is drawn.
	if globe and visible and Sim.native != null:
		_collect_patch()
	var me0: Node3D = _me()
	if follow and me0 != null:
		centre = Vector2(me0.global_position.x, me0.global_position.z)
	# Twice a second is plenty for a picture, and working out who can see what
	# is a line of sight march per pair.
	_contact_t -= d
	if _contact_t <= 0.0:
		_contact_t = DETECT_EVERY
		_refresh_contacts()
	queue_redraw()

## Was that click on something in orbit? Assigns it to the ASAT launchers if so
## and reports true, leaving the caller to do nothing else with the click.
func _pick_satellite(at: Vector2) -> bool:
	var vp := get_viewport_rect().size
	var ppm := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
	var org := vp * 0.5
	var hit: Node = null
	var best := 22.0
	for sat in get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		var q: Vector3 = (sat as Node3D).global_position
		var d: float = _w2s(Vector2(q.x, q.z), org, ppm).distance_to(at)
		if d < best:
			best = d
			hit = sat
	if hit == null:
		return false
	sat_target = null if sat_target == hit else hit
	Sim.sat_target = sat_target
	Sim.report("orbital target: %s" % (String(hit.call("display_name"))
		if sat_target != null else "released"), Sim.Ev.INFO)
	return true

func _w2s(p: Vector2, org: Vector2, px_per_m: float) -> Vector2:
	return org + (p - centre) * px_per_m

func _draw() -> void:
	if globe:
		_draw_globe()
		return
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.03, 0.04, 0.93), true)
	var org := vp * 0.5
	var ppm := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
	if _tex:
		var span := Vector2(HALF * 2.0, HALF * 2.0) * ppm
		draw_texture_rect(_tex, Rect2(_w2s(Vector2(-HALF, -HALF), org, ppm), span), false)
	# The close-in sheet over the top of it, wherever one of its texels is
	# still bigger than a pixel. Drawn under everything else, so the roads and
	# the towns and the contacts all sit on whichever sheet is showing.
	if _detail_tex and DETAIL_HALF * 2.0 / float(DETAIL_RES) * ppm > 0.4:
		var dspan := Vector2(DETAIL_HALF * 2.0, DETAIL_HALF * 2.0) * ppm
		draw_texture_rect(_detail_tex,
			Rect2(_w2s(Vector2(-DETAIL_HALF, -DETAIL_HALF), org, ppm), dspan), false)

	# runway
	var rw := Sim.RUNWAY_LEN * 0.5
	draw_line(_w2s(Vector2(0, -rw), org, ppm), _w2s(Vector2(0, rw), org, ppm),
		Color(0.95, 0.95, 0.95), maxf(2.0, Sim.RUNWAY_HALF_W * 2.0 * ppm))
	_label(_w2s(Vector2(0, rw + 400.0), org, ppm), "RWY 18/36", Color(0.9, 0.95, 1.0))

	# trunk roads over the top so the network reads at any zoom
	for r in Sim.ROADS:
		draw_line(_w2s(r[0], org, ppm), _w2s(r[1], org, ppm), Color(0.55, 0.5, 0.42, 0.8), 1.6)

	# Towns, as they were actually sited and wherever they are.
	#
	# This read the hand-written home list, which meant two things: every
	# settlement in the other four clusters -- half of them -- was missing from
	# the map entirely, and the sixteen it did draw were drawn where they had
	# been *asked* for rather than where they ended up, which is up to three
	# kilometres away once they have been moved onto workable ground.
	var sc := Scenery.current
	if sc != null:
		for t in sc.sites:
			var c: Vector2 = t["c"]
			var p := _w2s(c, org, ppm)
			var fac := Sim.region_faction(c.x, c.y)
			var col := Color(0.75, 0.72, 0.6, 0.7)
			if fac == "russia" or fac == "china":
				col = Color(0.95, 0.55, 0.45, 0.75)
			draw_arc(p, maxf(float(t["r"]) * ppm, 3.0), 0, TAU, 24, col, 1.2)
			_label(p + Vector2(6, -6), String(t["name"]),
				Color(col.r, col.g, col.b, 1.0))

	# Everyone in the session, by callsign.
	#
	# The map showed the ground and nothing on it: in a multiplayer game you
	# could not see where anybody was, including the people on your own side.
	if world != null and world.get("net") != null and (world.net as NetLink).active:
		for pl in (world.net as NetLink).player_positions():
			var e: Dictionary = pl
			var at: Vector3 = e["at"]
			if at == Vector3.INF:
				continue
			var q := _w2s(Vector2(at.x, at.z), org, ppm)
			var col := Color(0.40, 0.82, 1.0) if int(e["team"]) == 0 \
				else Color(1.0, 0.44, 0.36)
			if bool(e["me"]):
				col = Color(0.55, 1.0, 0.72)
			# a caret for anything airborne, a square for anything on the ground
			if String(e["kind"]) == "air":
				draw_polyline(PackedVector2Array([q + Vector2(-6, 5),
					q + Vector2(0, -6), q + Vector2(6, 5)]), col, 1.8)
			else:
				draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), col, false, 1.6)
			_label(q + Vector2(9, -7), String(e["name"]), col, 12)

	# contacts: ours always, theirs only while somebody of ours can account for it
	for c in _contacts:
		# Checked before it is typed. The list is rebuilt on a timer, so
		# anything shot down between two ticks is still in it -- and assigning a
		# freed instance to a typed variable is itself the error, before any
		# validity check gets the chance to run.
		var nv: Variant = c["n"]
		if not is_instance_valid(nv):
			continue
		var n: Node3D = nv
		var np: Vector3 = n.global_position
		var q2 := _w2s(Vector2(np.x, np.z), org, ppm)
		var hostile: bool = bool(c["hostile"])
		# Neutral shipping is neither ours nor theirs, and colouring it as an
		# enemy hid the fact that a container ship is something you can lock.
		var col2 := Color(0.42, 0.80, 1.0)
		if bool(c.get("neutral", false)):
			col2 = Color(0.85, 0.82, 0.45)          # neutral traffic
		elif hostile:
			col2 = Color(1.0, 0.44, 0.36)
		if tank != null and is_instance_valid(tank) and tank.map_lock == n:
			col2 = Color(1.0, 0.82, 0.25)
			draw_arc(q2, 11.0, 0.0, TAU, 20, col2, 1.6)
		if n is Aircraft:
			draw_polyline(PackedVector2Array([q2 + Vector2(-5, 4),
				q2 + Vector2(0, -5), q2 + Vector2(5, 4)]), col2, 1.5)
		else:
			draw_rect(Rect2(q2 - Vector2(3.5, 3.5), Vector2(7, 7)), col2, false, 1.4)

	# Whatever the weapon camera is riding, so a shot can be followed on the map
	# as well as over its shoulder.
	if world != null and is_instance_valid(world.get("cam")):
		# Held as a Variant until it has been checked. A camera that has just
		# finished riding a round still holds the reference for a frame, and
		# assigning a freed instance to a typed variable is an error in itself
		# -- the check has to come first.
		var riding_v: Variant = (world.cam as Node).get("weapon_cam")
		if riding_v != null and is_instance_valid(riding_v) and riding_v is Node3D:
			var riding: Node3D = riding_v
			var rp: Vector3 = (riding as Node3D).global_position
			var rq := _w2s(Vector2(rp.x, rp.z), org, ppm)
			var rc := Color(1.0, 0.85, 0.35)
			draw_arc(rq, 9.0, 0.0, TAU, 18, rc, 1.8)
			draw_line(rq - Vector2(13, 0), rq + Vector2(13, 0), rc, 1.2)
			draw_line(rq - Vector2(0, 13), rq + Vector2(0, 13), rc, 1.2)
			var nm2 := "ROUND"
			if "wid" in riding:
				nm2 = String(WeaponSpec.get_spec(String(riding.wid))["short"])
			_label(rq + Vector2(14, -8), nm2, rc, 12)

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
		if not is_instance_valid(n) or n == aircraft or n == _me():
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

	# where you are, and which way you are pointing -- in whatever you are in
	var me1: Node3D = _me()
	if me1 != null:
		var p := _w2s(Vector2(me1.global_position.x, me1.global_position.z), org, ppm)
		var fwd: Vector3 = -me1.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 11.0, p - dir * 6.0 + side * 6.0,
			p - dir * 6.0 - side * 6.0]), Color(0.4, 1.0, 0.5))
		_label(Vector2(24, vp.y - 96), "POS  %+.1f km E   %+.1f km N   ALT %d ft" % [
			me1.global_position.x * 0.001, -me1.global_position.z * 0.001,
			int(Sim.altitude(me1.global_position) * 3.28084)],
			Color(0.7, 1.0, 0.8))

	# artillery fire mission marker
	# where the strategic round has been sent
	# What is overhead. A satellite is not a ground contact and does not belong
	# in the contact list, but it is the only thing an ASAT launcher can shoot
	# at — so the map is where you find one and pick it.
	for sat in get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		var sp2: Vector3 = (sat as Node3D).global_position
		var s2 := _w2s(Vector2(sp2.x, sp2.z), org, ppm)
		var friendly: bool = int(sat.get("team")) == 0
		var satc := Color(0.45, 0.85, 1.0) if friendly else Color(1.0, 0.55, 0.35)
		if sat == sat_target:
			satc = Color(1.0, 0.9, 0.35)
			draw_arc(s2, 13.0, 0.0, TAU, 20, satc, 2.0)
		# a lozenge, so it does not read as an aircraft or a ship
		draw_line(s2 + Vector2(-7, 0), s2 + Vector2(0, -5), satc, 1.6)
		draw_line(s2 + Vector2(0, -5), s2 + Vector2(7, 0), satc, 1.6)
		draw_line(s2 + Vector2(7, 0), s2 + Vector2(0, 5), satc, 1.6)
		draw_line(s2 + Vector2(0, 5), s2 + Vector2(-7, 0), satc, 1.6)
		_label(s2 + Vector2(10, -6), "%s %d km" % [
			String(sat.get("kind")).to_upper(), int(sp2.y * 0.001)], satc, 11)
	if Sim.objective != Vector3.INF:
		var op := _w2s(Vector2(Sim.objective.x, Sim.objective.z), org, ppm)
		var oc := Color(1.0, 0.82, 0.25)
		draw_arc(op, 11.0, 0.0, TAU, 20, oc, 2.0)
		draw_line(op + Vector2(-16, 0), op + Vector2(16, 0), oc, 1.4)
		draw_line(op + Vector2(0, -16), op + Vector2(0, 16), oc, 1.4)
		_label(op + Vector2(14, -14), "OBJECTIVE", oc, 12)
	if strategic_mark != Vector3.INF:
		var sp := _w2s(Vector2(strategic_mark.x, strategic_mark.z), org, ppm)
		draw_arc(sp, 9.0, 0.0, TAU, 20, Color(1.0, 0.45, 0.2), 1.8)
		draw_line(sp - Vector2(13, 0), sp + Vector2(13, 0), Color(1.0, 0.45, 0.2), 1.4)
		draw_line(sp - Vector2(0, 13), sp + Vector2(0, 13), Color(1.0, 0.45, 0.2), 1.4)
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
		# and every warhead that has been given a mark of its own
		for wi in tank.mirv_marks.size():
			var wm: Vector3 = tank.mirv_marks[wi]
			var wp := _w2s(Vector2(wm.x, wm.z), org, ppm)
			draw_arc(wp, 9.0, 0, TAU, 16, Color(1.0, 0.75, 0.25), 1.4)
			draw_line(wp - Vector2(0, 9), wp + Vector2(0, 9), Color(1.0, 0.75, 0.25), 1.2)
			_label(wp + Vector2(12, 4), "RV%d" % (wi + 1), Color(1.0, 0.8, 0.4), 11)
		_label(Vector2(24, vp.y - 120), "right click to lay a fire mission"
			+ ("  ·  shift+right click assigns a warhead (%d)" % tank.mirv_marks.size()
				if tank.mirv_marks.size() > 0 else "  ·  shift+right click assigns a warhead"),
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
	_label(Vector2(24, 64),
		"wheel zoom   drag to pan   ctrl+click sets an objective   click a satellite to target it   M to close",
		Color(0.6, 0.7, 0.8), 14)
	# north arrow
	var na := Vector2(vp.x - 60.0, 70.0)
	draw_line(na + Vector2(0, 18), na - Vector2(0, 18), Color(0.9, 0.95, 1.0), 2.0)
	draw_colored_polygon(PackedVector2Array([na - Vector2(0, 22), na + Vector2(-6, -10),
		na + Vector2(6, -10)]), Color(0.9, 0.95, 1.0))
	_label(na + Vector2(-5, 36), "N", Color(0.9, 0.95, 1.0))

func _label(at: Vector2, t: String, col: Color, pt := 13) -> void:
	draw_string(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, pt, col)

# ---------------------------------------------------------------- globe mode
## The map as the planet rather than as a chart of one cap of it.
##
## The flat map is an azimuthal chart of the ground you are on, and it is right
## for laying a fire mission. What it cannot show is where any of it *is*: the
## world is a 1200 km square on a 12742 km ball, the ground drops 1300 m by the
## far corner, and none of that is visible on a chart that draws the whole thing
## as a rectangle. This draws the ball.
##
## Everything is projected through `_globe_at`, including the overlays, so the
## contacts and the objective land on the sphere with the ground they belong to
## and disappear round the back of it when they should.
## The planet, or the flat chart.
##
## Not a choice any more: the map is the planet whenever there is a planet. The
## chart was the map for as long as the world was a square of ground, and having
## both meant two pictures of one world drawn by two sets of code -- which is
## how they came to disagree about where things were. It is kept for `--flat`,
## which has no planet to draw.
var globe := true
## Rotation about the polar axis and away from looking straight down at the
## chart. Its origin is the pole: the ground is drawn as a cap centred on the
## origin, so the origin is the one point on this planet with a name.
var globe_spin := 0.0
var globe_tilt := 0.0
## On-screen size of the ball as a fraction of the smaller screen edge. One
## frames the whole planet; the world you fly is a twentieth of that across, so
## looking at the ground means zooming in.
var globe_zoom := 1.0

## Rings of latitude and meridians, as counts.
const GLOBE_RINGS := 64
const GLOBE_SEGS := 72

## The close-in level of detail.
##
## The globe samples one sheet of the whole planet however far it is zoomed. At
## the top of the zoom range the cap on screen is a couple of hundredths of a
## degree across -- about thirty kilometres -- and a whole-planet sheet has a
## handful of texels in it, so closing on somewhere showed the same picture
## bigger and blurrier rather than showing more of it. This bakes the part
## being looked at, at its own resolution, and lays it over the base globe.
const PATCH_RES := 512
## Quads across the patch. It covers a small cap, so it does not need the
## whole globe's tessellation to follow the curve.
const PATCH_GRID := 40
## How far the view may move before the patch is worth baking again, as a
## fraction of the patch's own span. Re-baking every frame of a drag would cost
## more than the detail is worth.
const PATCH_SLACK := 0.22
var _patch_tex: ImageTexture = null
## The window the texture we are holding covers: u0, u1, v0, v1.
var _patch_win := PackedFloat32Array()
## The window a bake is in flight for, empty when nothing is being baked.
var _patch_asked := PackedFloat32Array()
var _patch_t0 := 0
var _patch_ms := 0.0

## Open the map on the planet.
##
## This used to switch between two maps. There is one now: everything the flat
## chart drew is drawn on the planet -- the aerodromes, the towns, the
## objectives, the carrier, the contacts, the other players, the fire missions
## and their warhead marks -- and the roads are inked into the sheet it is
## painted with. Two pictures of one world, drawn by two sets of code, is how
## they came to disagree about where things were in the first place.
##
## The flat chart survives only for `--flat`, the legacy square world, which has
## no planet to draw.
func toggle_globe() -> void:
	if not visible:
		toggle()
	queue_redraw()

## Unit direction from the planet centre for a point on the ground, given where
## it is on the flat chart. The world's horizontal coordinates *are* the offsets
## from the axis, so this is the sphere point at that offset and nothing has to
## be unprojected.
func _globe_dir(w: Vector2) -> Vector3:
	# The chart's own projection, which is the one the ground is generated
	# against. This read
	#
	#     Vector3(w.x, sqrt(R*R - w.length_squared()), w.y).normalized()
	#
	# -- an orthographic inverse about `Vector3.UP`, from when the chart was
	# always at `UP` and the two agreed near the origin. The chart is now put on
	# whichever country the sortie is flown from, so this had every mark on the
	# planet map -- contacts, satellites, your own aeroplane -- projected as
	# though the world were somewhere it is not, about eleven hundred kilometres
	# out. The globe's own mesh is indexed from the chart; the things drawn over
	# it have to be as well.
	return Sim.chart_to_dir(w.x, w.y)

func _globe_basis() -> Basis:
	# Bring the chart's origin round to face the viewer, then let drag turn it
	# away from there.
	#
	# This used to rotate the planet's own up into view -- "the pole, the
	# chart's origin", which were the same direction for as long as the chart
	# was always at `Vector3.UP`. They are different things now: the chart is
	# put on whichever country the sortie is flown from, so opening the planet
	# map looked at a fixed point of the globe rather than at where you are.
	# Built from the chart's own frame, north is up on screen and east is
	# right, which is what a map is.
	var frame := Basis(Sim.chart_east, -Sim.chart_south,
		Sim.chart_origin).transposed()
	return Basis(Vector3.RIGHT, globe_tilt) * Basis(Vector3.UP, globe_spin) \
		* frame

## Screen position of a ground point, and whether it is on the near side. z > 0
## faces the viewer; anything else is round the back and must not be drawn.
func _globe_at(w: Vector2, org: Vector2, rad: float, b: Basis, lift := 1.0) -> Vector3:
	var v: Vector3 = b * _globe_dir(w)
	return Vector3(org.x + v.x * rad * lift, org.y - v.y * rad * lift, v.z)

## Where the sun is, in the same view frame, so the ball is lit the way the
## world is and the terminator falls where night does.
func _globe_light(b: Basis) -> Vector3:
	# The sun as a direction from the PLANET'S centre, which is the frame the
	# globe's own normals are in.
	#
	# `solar_angles` gives elevation and azimuth in the local horizon frame at
	# the chart's origin, and this used to hand that straight to the shading.
	# The two were the same thing while the chart sat on the planet's pole; they
	# are not now the chart is put on whichever country the sortie is flown
	# from. At 42 degrees south the globe was lit from a direction rotated by
	# that much -- measured, the disc came out brighter at midnight (0.122) than
	# at noon (0.083), which is the terminator drawn on the wrong side.
	#
	# Taken from the world's own light rather than worked out again: the world
	# frame *is* the local horizon frame at the chart's origin, so the light's
	# `basis.z` -- the direction toward the sun -- decomposes into up, east and
	# north there, and those three axes are known on the planet. No second
	# derivation, and no azimuth convention to get backwards.
	var w := Vector3(0.0, 0.9, -0.44)
	if world != null and is_instance_valid(world):
		var sun: Variant = world.get("_sun")
		if sun != null and is_instance_valid(sun) and sun is Node3D:
			w = (sun as Node3D).global_transform.basis.z
	if not Sim.globe:
		return (b * w).normalized()
	# up is +Y in the world frame, east is +X and north is -Z.
	var d: Vector3 = (Sim.chart_origin * w.y
		+ Sim.chart_east * w.x
		+ (-Sim.chart_south) * (-w.z)).normalized()
	return (b * d).normalized()

func _draw_globe() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.01, 0.015, 0.025, 0.96), true)
	var org := vp * 0.5
	var rad: float = minf(vp.x, vp.y) * 0.42 * globe_zoom
	var b := _globe_basis()
	var lit := _globe_light(b)
	_globe_body(org, rad, b, lit)
	_globe_patch(org, rad, b, lit)
	_globe_graticule(org, rad, b)
	_globe_marks(org, rad, b)
	# Whatever you are in, not the aeroplane: on a ship's bridge or in a tank
	# the readout was the parked aircraft's, or nothing.
	var me2: Node3D = _me()
	var alt := 0.0
	var lat := 0.0
	if me2 != null:
		var ap: Vector3 = me2.global_position
		alt = Sim.altitude(ap)
		lat = Sim.latitude_at(ap.x, ap.z)
	_label(Vector2(18, 26), "PLANET  —  drag to turn, wheel to zoom, right click "
		+ "to lay a fire mission", Color(0.75, 0.85, 1.0), 15)
	_label(Vector2(18, 48), "globe %.0f km across; you are %.1f km up at %.2f%s" % [
		Sim.PLANET_R * 2.0 * 0.001, alt * 0.001,
		absf(rad_to_deg(lat)), "N" if lat >= 0.0 else "S"],
		Color(0.6, 0.68, 0.78), 13)
	# The same position line the chart carries, so switching between the two
	# does not lose it.
	if me2 != null:
		var mp: Vector3 = me2.global_position
		_label(Vector2(24, vp.y - 96), "POS  %+.1f km E   %+.1f km N   ALT %d ft" % [
			mp.x * 0.001, -mp.z * 0.001, int(alt * 3.28084)],
			Color(0.7, 1.0, 0.8))

## The ball itself: ocean, shaded by the real sun. Emitted as one triangle array
## rather than a few thousand polygons, because it is redrawn every frame.
func _globe_body(org: Vector2, rad: float, b: Basis, lit: Vector3) -> void:
	# The generated planet: the globe reads the same equirectangular sheet the
	# orbital body does, so the map and the view out of the window are the same
	# world.
	#
	# The mesh is built in the extension. Written here it was four and a half
	# thousand quads -- eighteen thousand corners, each a little trigonometry
	# and a basis multiply -- rebuilt every frame the map is open, and the map
	# redraws every frame.
	var sheet: Texture2D = _planet_sheet()
	if sheet == null or Sim.native == null:
		return
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var mesh: Array = Sim.native.globe_mesh(GLOBE_RINGS, GLOBE_SEGS, org, rad,
		b, lit)
	_submit(mesh, sheet.get_rid())

## Hand a built mesh to the canvas.
func _submit(mesh: Array, tex: RID) -> void:
	if mesh.size() != 4:
		return
	var idx: PackedInt32Array = mesh[3]
	if idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), idx, mesh[0] as PackedVector2Array,
		mesh[2] as PackedColorArray, mesh[1] as PackedVector2Array,
		PackedInt32Array(), PackedFloat32Array(), tex)

## The part of the planet that is on screen, in sheet coordinates.
##
## Empty when the whole ball fits, because then the base sheet is already as
## much detail as the screen can show.
func _globe_window(rad: float, b: Basis) -> PackedFloat32Array:
	var vp := get_viewport_rect().size
	var half: float = minf(vp.x, vp.y) * 0.5
	if rad <= half * 1.25:
		return PackedFloat32Array()
	# The cap that reaches the corners of the screen, with a margin so a small
	# drag does not run off the edge of what has been baked.
	var ang: float = asin(clampf(half * 1.45 * sqrt(2.0) / rad, 0.0, 1.0))
	var pole: Vector3 = Sim.PLANET_NORTH
	var home := Vector3.UP
	var east: Vector3 = pole.cross(home).normalized()
	# Whichever way the globe has been turned, this is the point under the
	# middle of the screen.
	var c: Vector3 = (b.inverse() * Vector3(0.0, 0.0, 1.0)).normalized()
	var uvc: Vector2 = _globe_uv(c, pole, home, east)
	var dv: float = ang / PI
	var v0: float = uvc.y - dv
	var v1: float = uvc.y + dv
	# Meridians converge, so a cap of a given angle spans more longitude the
	# nearer the pole it is. Over the pole itself it spans all of them.
	var lat: float = (0.5 - uvc.y) * PI
	var span: float = cos(absf(lat)) 
	var du: float = 0.5 if v0 <= 0.0 or v1 >= 1.0 or span < 0.02 \
		else minf(ang / TAU / span, 0.5)
	return PackedFloat32Array([uvc.x - du, uvc.x + du,
		clampf(v0, 0.0, 1.0), clampf(v1, 0.0, 1.0)])

## Bake the window if what we are holding no longer covers it.
##
## Asked for, not waited on. The bake is half a million texels of the full
## height field -- forty milliseconds -- and done in line that is a hitch every
## time the map is zoomed or dragged. The extension bakes it on a thread of its
## own and this collects it when it is ready; until then the globe keeps
## drawing the patch it already has, or the base sheet if there is none yet.
func _want_patch(win: PackedFloat32Array) -> void:
	if Sim.native == null:
		return
	_collect_patch()
	if _patch_win.size() == 4:
		var wu: float = _patch_win[1] - _patch_win[0]
		var wv: float = _patch_win[3] - _patch_win[2]
		var nu: float = win[1] - win[0]
		var nv: float = win[3] - win[2]
		# Still good if it has not moved much and the zoom has not changed
		# enough to want a different scale.
		if absf(nu - wu) < wu * PATCH_SLACK and absf(nv - wv) < wv * PATCH_SLACK \
				and absf(win[0] - _patch_win[0]) < wu * PATCH_SLACK \
				and absf(win[2] - _patch_win[2]) < wv * PATCH_SLACK:
			return
	# One in flight at a time, and it is the newest window that is wanted: if
	# the view is still moving, the request that lands is the one made after it
	# stopped.
	if _patch_asked.size() == 4:
		_patch_asked = win.duplicate()
		return
	_patch_t0 = Time.get_ticks_usec()
	if Sim.native.patch_request(PATCH_RES, PATCH_RES, Sim.PLANET_NORTH,
			win[0], win[1], win[2], win[3]):
		_patch_asked = win.duplicate()

## Take delivery of a finished bake.
func _collect_patch() -> void:
	if _patch_asked.size() != 4 or not Sim.native.patch_ready():
		return
	var buf: PackedByteArray = Sim.native.patch_take()
	if buf.size() >= PATCH_RES * PATCH_RES * 3:
		var img := Image.create_from_data(PATCH_RES, PATCH_RES, false,
			Image.FORMAT_RGB8, buf)
		_patch_tex = ImageTexture.create_from_image(img)
		_patch_win = _patch_asked.duplicate()
		_patch_ms = float(Time.get_ticks_usec() - _patch_t0) * 0.001
	_patch_asked = PackedFloat32Array()
	queue_redraw()

## The detailed cap, drawn over the base globe.
func _globe_patch(org: Vector2, rad: float, b: Basis, lit: Vector3) -> void:
	var win := _globe_window(rad, b)
	if win.is_empty():
		return
	_want_patch(win)
	if _patch_tex == null or _patch_win.size() != 4:
		return
	var w := _patch_win
	var mesh: Array = Sim.native.globe_patch_mesh(PATCH_GRID,
		w[0], w[1], w[2], w[3], org, rad, b, lit)
	_submit(mesh, _patch_tex.get_rid())

## The inverse of `_globe_uv`: where a point of the sheet lies on the planet.
func _uv_dir(u: float, v: float, pole: Vector3, home: Vector3,
		east: Vector3) -> Vector3:
	var lat: float = (0.5 - v) * PI
	var lon: float = (u - 0.5) * TAU
	return (pole * sin(lat)
		+ (home * cos(lon) + east * sin(lon)) * cos(lat)).normalized()

func _globe_graticule(org: Vector2, rad: float, b: Basis) -> void:
	var col := Color(0.42, 0.55, 0.68, 0.35)
	# The frame the graticule is drawn in: the planet's north, and any two axes
	# across it. `u` is where a meridian starts, which is arbitrary -- what is
	# not arbitrary is that it is perpendicular to the pole.
	var pole: Vector3 = Sim.PLANET_NORTH
	var u0: Vector3 = Vector3.UP.cross(pole).normalized()
	if u0.length() < 0.5:
		u0 = Vector3.RIGHT.cross(pole).normalized()
	var v0: Vector3 = pole.cross(u0).normalized()
	for ring in range(1, 12):
		var th: float = PI * float(ring) / 12.0
		var run := PackedVector2Array()
		# The equator is the one worth seeing, so it is drawn heavier below.
		for j in range(GLOBE_SEGS + 1):
			var ph: float = TAU * float(j) / float(GLOBE_SEGS)
			var n: Vector3 = pole * cos(th) \
				+ (u0 * cos(ph) + v0 * sin(ph)) * sin(th)
			var v: Vector3 = b * n
			if v.z <= 0.0:
				if run.size() > 1:
					draw_polyline(run, col, 1.0)
				run = PackedVector2Array()
				continue
			run.append(Vector2(org.x + v.x * rad, org.y - v.y * rad))
		if run.size() > 1:
			draw_polyline(run, col, 1.0)
	# the equator, heavier, because it is the line the airfield sits on
	var eq := PackedVector2Array()
	for j2 in range(GLOBE_SEGS + 1):
		var ph3: float = TAU * float(j2) / float(GLOBE_SEGS)
		var n3: Vector3 = u0 * cos(ph3) + v0 * sin(ph3)
		var v3: Vector3 = b * n3
		if v3.z <= 0.0:
			if eq.size() > 1:
				draw_polyline(eq, Color(0.62, 0.78, 0.92, 0.55), 1.6)
			eq = PackedVector2Array()
			continue
		eq.append(Vector2(org.x + v3.x * rad, org.y - v3.y * rad))
	if eq.size() > 1:
		draw_polyline(eq, Color(0.62, 0.78, 0.92, 0.55), 1.6)
	for mer in range(12):
		var ph2: float = TAU * float(mer) / 12.0
		var run2 := PackedVector2Array()
		for i in range(GLOBE_RINGS + 1):
			var th2: float = PI * float(i) / float(GLOBE_RINGS)
			var n2: Vector3 = pole * cos(th2) \
				+ (u0 * cos(ph2) + v0 * sin(ph2)) * sin(th2)
			var v2: Vector3 = b * n2
			if v2.z <= 0.0:
				if run2.size() > 1:
					draw_polyline(run2, col, 1.0)
				run2 = PackedVector2Array()
				continue
			run2.append(Vector2(org.x + v2.x * rad, org.y - v2.y * rad))
		if run2.size() > 1:
			draw_polyline(run2, col, 1.0)

## Everything that is not the ground: where the world's works are, where you are,
## is on the map, and what is in orbit.
func _globe_marks(org: Vector2, rad: float, b: Basis) -> void:
	# the mapped square, so the ground under the chart can be picked out
	var edge := PackedVector2Array()
	var steps := 20
	for k in range(steps * 4 + 1):
		var t: float = float(k % (steps * 4)) / float(steps)
		var w := Vector2.ZERO
		if t < 1.0:
			w = Vector2(lerpf(-HALF, HALF, t), -HALF)
		elif t < 2.0:
			w = Vector2(HALF, lerpf(-HALF, HALF, t - 1.0))
		elif t < 3.0:
			w = Vector2(lerpf(HALF, -HALF, t - 2.0), HALF)
		else:
			w = Vector2(-HALF, lerpf(HALF, -HALF, t - 3.0))
		var p := _globe_at(w, org, rad, b)
		if p.z > 0.0:
			edge.append(Vector2(p.x, p.y))
		elif edge.size() > 1:
			draw_polyline(edge, Color(0.55, 0.75, 0.95, 0.6), 1.4)
			edge = PackedVector2Array()
	if edge.size() > 1:
		draw_polyline(edge, Color(0.55, 0.75, 0.95, 0.6), 1.4)
	# the airfield, which is the pole and the origin of everything else
	var home := _globe_at(Vector2.ZERO, org, rad, b)
	if home.z > 0.0:
		draw_arc(Vector2(home.x, home.y), 5.0, 0, TAU, 12,
			Color(0.9, 0.95, 1.0, 0.9), 1.6)
	# contacts, lifted to whatever height they are actually at
	for c in _contacts:
		# Validity before typing, as on the chart: the list is on a timer and
		# assigning a freed instance to a typed variable is itself the error.
		var nv: Variant = c["n"]
		if not is_instance_valid(nv):
			continue
		var n: Node3D = nv
		var np: Vector3 = n.global_position
		var lift0: float = 1.0 + maxf(Sim.altitude(np), 0.0) / Sim.PLANET_R
		var p2 := _globe_at(Vector2(np.x, np.z), org, rad, b, lift0)
		if p2.z <= 0.0:
			continue
		var col := Color(0.42, 0.80, 1.0)
		if bool(c.get("neutral", false)):
			col = Color(0.85, 0.82, 0.45)
		elif bool(c["hostile"]):
			col = Color(1.0, 0.44, 0.36)
		var here0 := Vector2(p2.x, p2.y)
		if n is Aircraft:
			draw_polyline(PackedVector2Array([here0 + Vector2(-4, 3),
				here0 + Vector2(0, -4), here0 + Vector2(4, 3)]), col, 1.4)
		else:
			draw_rect(Rect2(here0 - Vector2(2.5, 2.5), Vector2(5, 5)), col, true)
	# The aerodromes, the towns, the objectives and everyone in the session.
	#
	# These were on the flat chart only, so switching to the planet lost half of
	# what a tactical map is for. The chart was the map for as long as the world
	# was a square of ground; the planet is the map now, and everything the
	# chart drew has to be on it.
	#
	# The roads are not here: the network is fifty thousand legs and the map
	# redraws every frame, so they are inked into the sheet when it is baked.
	for fd in Sim.fields:
		var f: Dictionary = fd
		var at: Vector2 = f["at"]
		var yaw: float = float(f["yaw"])
		var half: float = Sim.RUNWAY_LEN * 0.5
		var along := Vector2(-sin(yaw), cos(yaw)) * half
		var pa := _globe_at(at - along, org, rad, b)
		var pb := _globe_at(at + along, org, rad, b)
		if pa.z <= 0.0 or pb.z <= 0.0:
			continue
		var who := String(f.get("who", ""))
		var fcol := Color(0.95, 0.95, 0.95) if who == Sim.home_faction \
			else Color(0.85, 0.78, 0.62)
		draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y), fcol, 2.0)
		_label(Vector2(pb.x, pb.y) + Vector2(6, -6),
			who.to_upper() if who != "" else "RWY", fcol, 12)
	var sc := Scenery.current
	if sc != null:
		for t in sc.sites:
			var c: Vector2 = t["c"]
			var p := _globe_at(c, org, rad, b)
			if p.z <= 0.0:
				continue
			var fac := Sim.region_faction(c.x, c.y)
			var col := Color(0.75, 0.72, 0.6, 0.7)
			if fac == "russia" or fac == "china":
				col = Color(0.95, 0.55, 0.45, 0.75)
			var here2 := Vector2(p.x, p.y)
			# Radius on the screen the same way the chart works it out: the
			# globe is `rad` px for the planet's radius.
			draw_arc(here2, maxf(float(t["r"]) / Sim.PLANET_R * rad, 2.0),
				0, TAU, 18, col, 1.2)
			if rad > 900.0:
				_label(here2 + Vector2(5, -5), String(t["name"]),
					Color(col.r, col.g, col.b, 1.0), 12)
	for z in get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		var zp: Vector3 = z.global_position
		var p := _globe_at(Vector2(zp.x, zp.z), org, rad, b)
		if p.z <= 0.0:
			continue
		var col := Color(0.8, 0.8, 0.82)
		if z.owner_team == 0:
			col = Color(0.35, 0.75, 1.0)
		elif z.owner_team == 1:
			col = Color(1.0, 0.35, 0.3)
		draw_arc(Vector2(p.x, p.y),
			maxf(float(z.radius) / Sim.PLANET_R * rad, 6.0), 0, TAU, 28, col, 1.8)
		_label(Vector2(p.x, p.y) - Vector2(4, 8), str(z.label), col)
	# Whatever the weapon camera is riding, so a shot can be followed on the
	# map as well as over its shoulder. Lifted by its own altitude, because a
	# round in flight is the one contact that is mostly not on the ground.
	if world != null and is_instance_valid(world.get("cam")):
		# Held as a Variant until it has been checked. A camera that has just
		# finished riding a round still holds the reference for a frame, and
		# assigning a freed instance to a typed variable is an error in itself.
		var riding_v: Variant = (world.cam as Node).get("weapon_cam")
		if riding_v != null and is_instance_valid(riding_v) and riding_v is Node3D:
			var riding: Node3D = riding_v
			var rp: Vector3 = riding.global_position
			var rl: float = 1.0 + maxf(Sim.altitude(rp), 0.0) / Sim.PLANET_R
			var p := _globe_at(Vector2(rp.x, rp.z), org, rad, b, rl)
			if p.z > 0.0:
				var rq := Vector2(p.x, p.y)
				var rc := Color(1.0, 0.85, 0.35)
				draw_arc(rq, 9.0, 0.0, TAU, 18, rc, 1.8)
				draw_line(rq - Vector2(13, 0), rq + Vector2(13, 0), rc, 1.2)
				draw_line(rq - Vector2(0, 13), rq + Vector2(0, 13), rc, 1.2)
				# a tether to the ground under it, as the satellites have: a
				# round at forty kilometres is nowhere near what is beneath it
				var rfoot := _globe_at(Vector2(rp.x, rp.z), org, rad, b)
				draw_line(rq, Vector2(rfoot.x, rfoot.y),
					Color(rc.r, rc.g, rc.b, 0.35), 1.0)
				var nm2 := "ROUND"
				if "wid" in riding:
					nm2 = String(WeaponSpec.get_spec(String(riding.wid))["short"])
				_label(rq + Vector2(14, -8), nm2, rc, 12)
	if world and is_instance_valid(world.get("carrier")):
		var cp: Vector3 = world.carrier.global_position
		var p := _globe_at(Vector2(cp.x, cp.z), org, rad, b)
		if p.z > 0.0:
			draw_rect(Rect2(Vector2(p.x, p.y) - Vector2(5, 5), Vector2(10, 10)),
				Color(0.6, 0.8, 1.0), false, 1.6)
			_label(Vector2(p.x, p.y) + Vector2(9, 4), "CVN",
				Color(0.6, 0.8, 1.0))
	if world != null and world.get("net") != null \
			and (world.net as NetLink).active:
		for pl in (world.net as NetLink).player_positions():
			var e: Dictionary = pl
			var at3: Vector3 = e["at"]
			if at3 == Vector3.INF:
				continue
			var lift3: float = 1.0 + maxf(Sim.altitude(at3), 0.0) / Sim.PLANET_R
			var p := _globe_at(Vector2(at3.x, at3.z), org, rad, b, lift3)
			if p.z <= 0.0:
				continue
			var q3 := Vector2(p.x, p.y)
			var col := Color(0.40, 0.82, 1.0) if int(e["team"]) == 0 \
				else Color(1.0, 0.44, 0.36)
			if bool(e["me"]):
				col = Color(0.55, 1.0, 0.72)
			if String(e["kind"]) == "air":
				draw_polyline(PackedVector2Array([q3 + Vector2(-6, 5),
					q3 + Vector2(0, -6), q3 + Vector2(6, 5)]), col, 1.8)
			else:
				draw_rect(Rect2(q3 - Vector2(4, 4), Vector2(8, 8)), col, false, 1.6)
			_label(q3 + Vector2(9, -7), String(e["name"]), col, 12)
	# The fire mission and the warhead marks. Right click lays them and this is
	# where they show; without them the planet map could not do the one thing
	# the chart could do that reading the ground cannot.
	if strategic_mark != Vector3.INF:
		var sp3 := _globe_at(Vector2(strategic_mark.x, strategic_mark.z),
			org, rad, b)
		if sp3.z > 0.0:
			var sq := Vector2(sp3.x, sp3.y)
			var sc3 := Color(1.0, 0.45, 0.2)
			draw_arc(sq, 9.0, 0.0, TAU, 20, sc3, 1.8)
			draw_line(sq - Vector2(13, 0), sq + Vector2(13, 0), sc3, 1.4)
			draw_line(sq - Vector2(0, 13), sq + Vector2(0, 13), sc3, 1.4)
	if tank != null and is_instance_valid(tank) and tank.is_indirect():
		var tq3 := _globe_at(Vector2(tank.global_position.x,
			tank.global_position.z), org, rad, b)
		if tq3.z > 0.0:
			draw_rect(Rect2(Vector2(tq3.x, tq3.y) - Vector2(4, 4),
				Vector2(8, 8)), Color(0.4, 1.0, 0.5), false, 2.0)
		if tank.map_target != Vector3.INF:
			var mq := _globe_at(Vector2(tank.map_target.x, tank.map_target.z),
				org, rad, b)
			if mq.z > 0.0:
				var mp3 := Vector2(mq.x, mq.y)
				var mc := Color(1.0, 0.5, 0.2)
				draw_line(mp3 - Vector2(10, 10), mp3 + Vector2(10, 10), mc, 2.0)
				draw_line(mp3 - Vector2(10, -10), mp3 + Vector2(10, -10), mc, 2.0)
				draw_arc(mp3, 14.0, 0, TAU, 20, mc, 1.5)
				if tq3.z > 0.0:
					draw_line(Vector2(tq3.x, tq3.y), mp3,
						Color(mc.r, mc.g, mc.b, 0.5), 1.2)
				_label(mp3 + Vector2(18, 4), "%.1f km" % (
					tank.global_position.distance_to(tank.map_target) * 0.001),
					Color(1.0, 0.6, 0.3))
		for wi in tank.mirv_marks.size():
			var wm3: Vector3 = tank.mirv_marks[wi]
			var wq := _globe_at(Vector2(wm3.x, wm3.z), org, rad, b)
			if wq.z <= 0.0:
				continue
			var wp3 := Vector2(wq.x, wq.y)
			var wc := Color(1.0, 0.75, 0.25)
			draw_arc(wp3, 9.0, 0, TAU, 16, wc, 1.4)
			draw_line(wp3 - Vector2(0, 9), wp3 + Vector2(0, 9), wc, 1.2)
			_label(wp3 + Vector2(12, 4), "RV%d" % (wi + 1),
				Color(1.0, 0.8, 0.4), 11)
	# and the satellites, off the surface by their own altitude
	for sat in get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		var q: Vector3 = (sat as Node3D).global_position
		var lift: float = 1.0 + Sim.altitude(q) / Sim.PLANET_R
		var p3 := _globe_at(Vector2(q.x, q.z), org, rad, b, lift)
		if p3.z <= 0.0:
			continue
		var here := Vector2(p3.x, p3.y)
		var hot: bool = sat == sat_target
		var col2 := Color(1.0, 0.55, 0.35) if hot else Color(0.6, 0.9, 1.0)
		draw_arc(here, 4.0, 0, TAU, 10, col2, 1.4)
		# a tether down to the ground under it, or an orbit reads as a contact
		var foot := _globe_at(Vector2(q.x, q.z), org, rad, b)
		draw_line(here, Vector2(foot.x, foot.y),
			Color(col2.r, col2.g, col2.b, 0.35), 1.0)
	# the player, last so it is on top
	var me: Node3D = _me()
	if me != null:
		var a: Vector3 = me.global_position
		var lift2: float = 1.0 + maxf(Sim.altitude(a), 0.0) / Sim.PLANET_R
		var pa := _globe_at(Vector2(a.x, a.z), org, rad, b, lift2)
		if pa.z > 0.0:
			draw_arc(Vector2(pa.x, pa.y), 6.0, 0, TAU, 14,
				Color(0.35, 1.0, 0.55), 2.0)

## Whatever the player is in.
##
## `aircraft` is set when a sortie starts and never changed, so on the carrier's
## bridge -- or in a tank, or on foot -- the map either marked an empty parked
## aeroplane or marked nothing at all. The world knows what you are in; ask it,
## and fall back to the aeroplane for the cases that have no world (the menu
## turntable, the tests).
func _me() -> Node3D:
	if world != null and is_instance_valid(world) and world.has_method("controlled"):
		var n: Node3D = world.call("controlled")
		if n != null and is_instance_valid(n):
			return n
	if aircraft != null and is_instance_valid(aircraft):
		return aircraft as Node3D
	return null

## Where a click on the globe lands on the ground, in chart coordinates.
##
## The inverse of `_globe_at` for a point on the surface: undo the screen scale
## to get the ball-relative x and y, put the point on the near side of the unit
## sphere, turn it back through the view, and ask the chart where that is.
## Returns an infinite pair for a click off the ball.
func _globe_point(at: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var org := vp * 0.5
	var rad: float = minf(vp.x, vp.y) * 0.42 * globe_zoom
	var d: Vector2 = (at - org) / maxf(rad, 1e-6)
	var r2: float = d.x * d.x + d.y * d.y
	if r2 > 1.0:
		return Vector2(INF, INF)
	var v := Vector3(d.x, -d.y, sqrt(maxf(1.0 - r2, 0.0)))
	var dir: Vector3 = (_globe_basis().inverse() * v).normalized()
	return Sim.dir_to_chart(dir)

## `_contact_near`, through the globe's projection.
func _contact_near_globe(at: Vector2) -> Node:
	var vp := get_viewport_rect().size
	var org := vp * 0.5
	var rad: float = minf(vp.x, vp.y) * 0.42 * globe_zoom
	var b := _globe_basis()
	var best: Node = null
	var bd := 18.0
	for c in _contacts:
		var nv: Variant = c["n"]
		if not is_instance_valid(nv):
			continue
		var n: Node3D = nv
		var p: Vector3 = n.global_position
		var lift: float = 1.0 + maxf(Sim.altitude(p), 0.0) / Sim.PLANET_R
		var q := _globe_at(Vector2(p.x, p.z), org, rad, b, lift)
		if q.z <= 0.0:
			continue
		var d: float = Vector2(q.x, q.y).distance_to(at)
		if d < bd:
			bd = d
			best = n
	return best

## The same pick as on the chart, through the globe's own projection. Anything
## round the back of the planet is not clickable, which is the point of drawing
## a planet at all.
func _pick_satellite_globe(at: Vector2) -> void:
	var vp := get_viewport_rect().size
	var org := vp * 0.5
	var rad: float = minf(vp.x, vp.y) * 0.42 * globe_zoom
	var b := _globe_basis()
	var hit: Node = null
	var best := 22.0
	for sat in get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		var q: Vector3 = (sat as Node3D).global_position
		var lift: float = 1.0 + Sim.altitude(q) / Sim.PLANET_R
		var p := _globe_at(Vector2(q.x, q.z), org, rad, b, lift)
		if p.z <= 0.0:
			continue
		var d: float = Vector2(p.x, p.y).distance_to(at)
		if d < best:
			best = d
			hit = sat
	if hit == null:
		return
	sat_target = null if sat_target == hit else hit
	Sim.sat_target = sat_target
	Sim.report("orbital target: %s" % (String(hit.call("display_name"))
		if sat_target != null else "released"), Sim.Ev.INFO)

## Where a direction from the planet's centre falls on the planet sheet.
##
## Plain equirectangular: longitude east of the chart origin across, latitude north
## of it down. Longitude is measured from the chart origin so the world lands on the
## planet where the world is, and the airfield lands on the airfield.
func _globe_uv(n: Vector3, pole: Vector3, home: Vector3, east: Vector3) -> Vector2:
	var lat: float = asin(clampf(n.dot(pole), -1.0, 1.0))
	var lon: float = atan2(n.dot(east), n.dot(home))
	return Vector2(lon / TAU + 0.5, 0.5 - lat / PI)

## The planet's own sheet, from the body that generated it.
func _planet_sheet() -> Texture2D:
	if world != null and is_instance_valid(world):
		var p: Variant = world.get("planet")
		if p != null and is_instance_valid(p):
			return p.get("sheet") as Texture2D
	return null
