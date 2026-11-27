class_name MapView
extends Control
## Tactical map on M. The background is baked once from the same height and
## biome fields the terrain uses, with hill shading; everything else is drawn
## live on top.

## See `MapGlobe`.
var globe_view := MapGlobe.new(self)

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
## Far enough in to tell one street from the next. Four hundred was the limit,
## which on a six hundred kilometre sheet is two metres to the pixel: a whole
## street fight in a patch the size of a thumbnail.
const MAX_ZOOM := 9000.0
const GLOBE_MAX := 30000.0
## The globe and the chart are one zoom.
##
## They were two maps. The globe is the planet and has nothing on it to fight
## by; the chart has the streets and could not be zoomed out past twelve
## hundred kilometres -- and the only way onto it was choosing a target for a
## strike, after which there was no way back to the planet at all. Over the
## theatre, which is the ground the chart has, zooming the globe in past this
## hands over to the chart at the same place and the same scale, and zooming
## the chart out past it hands back. Elsewhere on the planet the globe simply
## carries on zooming, as it always did. The chart zoom it happens at is about
## three hundred kilometres across the screen; the globe hands over a little
## further in, so a single notch of the wheel never flips it back and forth.
const HANDOVER := 4.0
const HANDOVER_IN := 4.6
## Somebody waiting for a place to be chosen: the next plain click on the
## chart is handed to this as a point on the ground, and the map closes.
var pick_cb: Callable = Callable()
var pick_label := ""
## The first end of a two click pick (a carpet's line), while the second is awaited.
var pick_from := Vector3.INF
## Where support has been called down: {at, from, label, until (msec)}.
var pick_marks: Array = []
## How long the mark just laid should stay, set by whoever was called back
## with it: a number of seconds, or the thing it was laid for, in which case
## the mark goes when that does. Nothing set means half a minute.
var pick_life: Variant = null
var _close_tok := 0

## Chart zoom for a globe zoom at the same scale in the middle of the screen,
## and back. The chart is `0.86 * zoom` screens to its `2 * HALF` metres; the
## globe is `0.42 * globe_zoom` screens to the planet's radius.
## How far out the planet map will go. Far enough to see the planet whole,
## which was all there was to see -- and, with something of yours in space,
## far enough to see the moon and the road to it.
## The rocket being flown, if one is.
func _crewed_rocket() -> LaunchVehicle:
	for n in get_tree().get_nodes_in_group("rockets"):
		var lv := n as LaunchVehicle
		if lv != null and lv.occupied:
			return lv
	return null

func _globe_min() -> float:
	if not get_tree().get_nodes_in_group("rockets").is_empty():
		return 0.012
	return 0.6

## Where a point in the planet's own frame falls on the planet map: screen x
## and y, and in z whether it can be seen -- positive in front of the ball or
## clear of its edge, negative only when it is round the back and hidden by it.
func _space_at(p: Vector3, org: Vector2, rad: float, b: Basis) -> Vector3:
	var v: Vector3 = b * (p / Sim.PLANET_R)
	var seen: float = 1.0
	if v.z < 0.0 and Vector2(v.x, v.y).length() < 1.0:
		seen = -1.0
	return Vector3(org.x + v.x * rad, org.y - v.y * rad, seen)

## A path through space, as a line that goes behind the planet where it does.
func _space_line(path: PackedVector3Array, org: Vector2, rad: float, b: Basis,
		col: Color, width := 1.6) -> void:
	var prev := Vector3.ZERO
	var have := false
	for p in path:
		var q := _space_at(p, org, rad, b)
		if have and prev.z > 0.0 and q.z > 0.0:
			draw_line(Vector2(prev.x, prev.y), Vector2(q.x, q.y), col, width, true)
		prev = q
		have = true

## What is in space, drawn round the planet: the moon where it is, the path
## each rocket of yours is on if nothing more is done to it, and where every
## warhead in the air is going to come down.
##
## The lines are the flight worked out ahead -- the same sums that fly it, run
## forward -- not a shape assumed for it. A rocket still climbing shows the arc
## that falls back; one that has made orbit shows the lap, closed; one on its
## way to the moon shows the long reach out, bent at the far end where the
## moon takes hold.
func _globe_space(org: Vector2, rad: float, b: Basis) -> void:
	var rockets: Array = get_tree().get_nodes_in_group("rockets")
	var shots: Array = get_tree().get_nodes_in_group("icbm")
	if rockets.is_empty() and shots.is_empty():
		return
	var moon_p: Vector3 = Sim.moon_dir() * Sim.MOON_DIST
	var mq := _space_at(moon_p, org, rad, b)
	var mr: float = maxf(rad * Sim.MOON_R / Sim.PLANET_R, 2.5)
	if mq.z > 0.0 and Rect2(Vector2(-200, -200), get_viewport_rect().size
			+ Vector2(400, 400)).has_point(Vector2(mq.x, mq.y)):
		draw_circle(Vector2(mq.x, mq.y), mr, Color(0.62, 0.62, 0.60))
		draw_arc(Vector2(mq.x, mq.y), mr, 0, TAU, 32, Color(0.85, 0.85, 0.82), 1.2)
		_label(Vector2(mq.x + mr + 6.0, mq.y + 4.0), "MOON", Color(0.85, 0.85, 0.82), 12)
		# the road it goes round on, faintly
		var ring := PackedVector3Array()
		var ax: Vector3 = Sim.MOON_AXIS.normalized()
		var u: Vector3 = ax.cross(Vector3.RIGHT).normalized()
		var w: Vector3 = ax.cross(u)
		for i in 97:
			var a: float = TAU * float(i) / 96.0
			ring.append((u * cos(a) + w * sin(a)) * Sim.MOON_DIST)
		_space_line(ring, org, rad, b, Color(0.6, 0.6, 0.6, 0.22), 1.0)
	for n in rockets:
		var lv := n as LaunchVehicle
		if lv == null or not lv.alive:
			continue
		_space_line(lv.path_ahead(), org, rad, b, Color(0.45, 1.0, 0.65, 0.9), 1.8)
		var at := _space_at(lv.space_pos(), org, rad, b)
		if at.z > 0.0:
			draw_circle(Vector2(at.x, at.y), 4.0, Color(0.45, 1.0, 0.65))
			_label(Vector2(at.x + 8.0, at.y - 6.0), lv.display_name().to_upper(),
				Color(0.45, 1.0, 0.65), 12)
			for mk in lv.path_marks():
				var mp := _space_at(mk[1], org, rad, b)
				if mp.z > 0.0:
					draw_arc(Vector2(mp.x, mp.y), 3.5, 0, TAU, 10, Color(0.8, 1.0, 0.85), 1.2)
					_label(Vector2(mp.x + 7.0, mp.y + 12.0), String(mk[0]),
						Color(0.8, 1.0, 0.85), 11)
	for n2 in shots:
		var m := n2 as Icbm
		if m == null or m.dead:
			continue
		var col := Color(1.0, 0.72, 0.36, 0.9) if m.team == 0 else Color(1.0, 0.4, 0.35, 0.9)
		_space_line(m.path_ahead(), org, rad, b, col, 1.3)
		var mat := _space_at(m.space_pos(), org, rad, b)
		if mat.z > 0.0:
			draw_circle(Vector2(mat.x, mat.y), 2.6, col)

func _chart_zoom_for(gz: float) -> float:
	return gz * 0.42 * HALF * 2.0 / (0.86 * Sim.PLANET_R)

func _globe_zoom_for(z: float) -> float:
	return z * 0.86 * Sim.PLANET_R / (0.42 * HALF * 2.0)

## After any zoom: across to the other map if it has gone past the handover.
func _handover() -> void:
	if not Sim.globe:
		return
	if globe:
		var cz: float = _chart_zoom_for(globe_zoom)
		if cz < HANDOVER_IN:
			return
		var vp := get_viewport_rect().size
		var w: Vector2 = _globe_point(vp * 0.5)
		if not w.is_finite():
			return
		# Only where the chart has ground for the whole of the screen.
		var half_view: float = maxf(vp.x, vp.y) * 0.5 \
			/ (minf(vp.x, vp.y) * 0.86 * cz / (HALF * 2.0))
		if maxf(absf(w.x), absf(w.y)) + half_view > HALF:
			return
		globe = false
		centre = w
		zoom = cz
		follow = false
	else:
		if zoom >= HANDOVER:
			return
		_aim_globe(centre)
		globe_zoom = _globe_zoom_for(zoom)
		globe = true
	queue_redraw()

## Turn the globe so a point on the chart is in the middle of the screen: the
## inverse of `_globe_basis` for that one direction. Spin about the vertical
## brings it round to the front, tilt brings it up to the middle.
func _aim_globe(w: Vector2) -> void:
	var frame := Basis(Sim.chart_east, -Sim.chart_south,
		Sim.chart_origin).transposed()
	var v: Vector3 = frame * globe_view._globe_dir(w)
	globe_spin = atan2(-v.x, v.z)
	globe_tilt = clampf(atan2(v.y, sqrt(v.x * v.x + v.z * v.z)), -PI * 0.49, PI * 0.49)

## Open on the player, close enough in to see a street, and wait for a click.
func pick(label: String, cb: Callable) -> void:
	pick_cb = cb
	pick_label = label
	globe = false
	if not visible:
		toggle()
	follow = true
	zoom = maxf(zoom, 2400.0)
	queue_redraw()

func cancel_pick() -> void:
	pick_cb = Callable()
	pick_label = ""
	pick_from = Vector3.INF
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
	if Sim.globe:
		# The planet's ground, from the planet's rasteriser -- the one the
		# close-in sheet is drawn with. This took the flat world's picture off
		# the disk instead, so until the chart first moved the map was two
		# worlds: zoom out and it was the old 1200 km field's biomes, zoom in
		# to where the buildings show and it was the planet's, and the country
		# changed colour under you at the hand-over between the sheets. Not
		# kept on disk either: it is a picture of wherever the chart is.
		buf = Sim.native.map_relief_globe(RES, HALF)
	elif cached is PackedByteArray and (cached as PackedByteArray).size() == RES * RES * 3:
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
	# The close-in sheet is asked for rather than waited on.
	#
	# Four million texels of relief is half a second of the two and a half the
	# whole world takes to build, and nobody opens the tactical map in the first
	# second of a sortie. The map draws the coarse sheet until this lands, and
	# anything that genuinely needs it -- a harness saving it to a file -- waits
	# for it in `detail`.
	if Sim.globe:
		_ask_sheet()
	else:
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

## Asked for and not yet arrived, and whether the chart moved again while it
## was being drawn.
var _sheet_want := false
var _sheet_again := false

## The chart has moved: the close-in sheet is of somewhere else now.
##
## Asked for, not waited on. Four million texels of relief is a fifth of a
## second on eight cores and it used to happen on the frame the chart moved --
## measured, a chart move was a 1352 ms freeze in flight and 1183 ms of it was
## this one call. The map goes on drawing the sheet it has until the new one
## lands, which is a picture a few seconds out of date rather than a second and
## a third of nothing at all.
func rechart() -> void:
	if not Sim.globe:
		return
	# The world sheet as well, and this one in line.
	#
	# Both sheets are pictures of the ground under the *chart*, and only the
	# close-in one was being redrawn -- so after a chart move the map had six
	# hundred kilometres of the country it had just left with the new country's
	# hundred and twenty painted in the middle of it. It does not read as a
	# stale picture, it reads as the map jumping. A quarter of a million texels
	# against the close-in sheet's four million, so it is quick enough to do
	# where it is noticed rather than a few seconds later.
	_tex = _bake_sheet("map_relief", RES, HALF)
	if not _ask_sheet():
		# The last one is still being drawn. It is of the chart before this one
		# and is already wrong, but cancelling a thread is worse than letting it
		# finish; this asks again the moment it does.
		_sheet_again = true
	queue_redraw()

func _ask_sheet() -> bool:
	if not Sim.native.sheet_request(DETAIL_RES, DETAIL_HALF):
		return false
	_sheet_want = true
	_sheet_again = false
	return true

## Take a finished sheet, if there is one.
##
## Pumped every frame by the world rather than from `_process` here, which only
## runs while the map is open: the sheet is wanted whenever the map is *next*
## opened, and one left sitting in the slot until then would be a picture of
## somewhere the chart has since left.
func pump_sheet() -> void:
	if _sheet_want and Sim.native.sheet_ready():
		var buf: PackedByteArray = Sim.native.sheet_take()
		if buf.size() == DETAIL_RES * DETAIL_RES * 3:
			_detail_tex = ImageTexture.create_from_image(
				Image.create_from_data(DETAIL_RES, DETAIL_RES, false,
					Image.FORMAT_RGB8, buf))
			queue_redraw()
		_sheet_want = false
	if _sheet_again and not _sheet_want:
		_ask_sheet()

## The close-in sheet, for anything that wants the ground under the chart.
##
## Waits for a bake in flight if there is nothing to hand back yet. The map
## itself never comes through here -- it draws whatever sheet it has and takes
## the new one when it arrives -- but a harness that saves the sheet to a file
## wants the real thing rather than whatever had turned up by then.
func detail() -> ImageTexture:
	while _sheet_want and _detail_tex == null:
		OS.delay_msec(2)
		pump_sheet()
	return _detail_tex

func toggle() -> void:
	visible = not visible
	# From a spacecraft the planet map opens tipped over. It opens looking
	# straight down on wherever you are, which for an aeroplane is the point;
	# for something in orbit it is the one direction from which the orbit is a
	# straight line across the planet and the way to the moon is hidden behind
	# it. Tipped, a lap is an ellipse and the reach out to the moon has length.
	if visible and _crewed_rocket() != null:
		globe = true
		globe_tilt = 0.95
		globe_spin = 0.35
	if not visible:
		cancel_pick()
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
	# Men on foot as well. They are kept off the radar picture on purpose, but
	# a map of a street fight with nobody on it is a map of some buildings.
	for n in get_tree().get_nodes_in_group("hittable") + get_tree().get_nodes_in_group("infantry"):
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
	# Everything in `mine` is side 0, so the side's reach is one number: asked
	# inside the loops it was three walks of the tree for every pair of units.
	var air_reach: float = maxf(Sim.coverage(0), 26000.0)
	for h in theirs:
		var p: Vector3 = (h as Node3D).global_position
		# The strike range is a range: its targets are on the chart from the
		# start, or the last of a wave is a hunt for something you cannot see.
		var seen: bool = (h as Node).has_meta("strike")
		for f2 in mine:
			if seen:
				break
			var fp: Vector3 = (f2 as Node3D).global_position
			var d: float = fp.distance_to(p)
			# an aeroplane carries a radar; anything else has to be able to see it
			# The side's whole picture, not just this airframe's own set: a
			# satellite or an early warning aircraft widens what the map shows,
			# which is most of the reason for having either.
			var reach: float = air_reach if f2 is Aircraft else 14000.0
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
	var bd := 26.0
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
	# The globe turns and zooms with the plain buttons, and the modified and
	# right clicks do what they do on the chart: an objective, a fire mission,
	# an aiming point, a satellite.
	if globe:
		# A trackpad does not send wheel buttons. Two fingers on a Mac trackpad
		# is a pan gesture and a pinch is a magnify, and with neither handled
		# the map simply could not be zoomed on a laptop.
		if e is InputEventPanGesture:
			globe_zoom = clampf(globe_zoom * pow(1.08,
				-(e as InputEventPanGesture).delta.y), _globe_min(), GLOBE_MAX)
			_handover()
			queue_redraw()
			return
		if e is InputEventMagnifyGesture:
			globe_zoom = clampf(
				globe_zoom * (e as InputEventMagnifyGesture).factor, _globe_min(), GLOBE_MAX)
			_handover()
			queue_redraw()
			return
		if e is InputEventMouseButton:
			var gb := e as InputEventMouseButton
			if gb.button_index == MOUSE_BUTTON_WHEEL_UP and gb.pressed:
				globe_zoom = clampf(globe_zoom * 1.2, _globe_min(), GLOBE_MAX)
				_handover()
			elif gb.button_index == MOUSE_BUTTON_WHEEL_DOWN and gb.pressed:
				globe_zoom = clampf(globe_zoom / 1.2, _globe_min(), GLOBE_MAX)
			elif gb.button_index == MOUSE_BUTTON_RIGHT and gb.pressed:
				# Something on the ground under the cursor first. Zoomed out, the
				# whole theatre is a few pixels of globe with the satellites
				# passing over it, and the satellite pick came first: a right
				# click on a red dot to lock a fire mission onto it selected
				# whichever satellite was overhead instead.
				if _contact_near_globe(gb.position) != null \
						or not _pick_satellite_globe(gb.position):
					_lay_mark(gb)
			elif gb.button_index == MOUSE_BUTTON_LEFT and gb.pressed \
					and (gb.shift_pressed or gb.ctrl_pressed or gb.meta_pressed):
				# An objective, where the click lands on the ground. The map
				# has only been the globe for a while and this branch took
				# every click for turning it, so the objective marker -- which
				# lived on the flat chart's side -- could not be set at all.
				_objective_at(gb.position)
				return
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
			-(e as InputEventPanGesture).delta.y), 1.0, MAX_ZOOM)
		follow = false
		_handover()
		queue_redraw()
		return
	if e is InputEventMagnifyGesture:
		zoom = clampf(zoom * (e as InputEventMagnifyGesture).factor, 1.0, MAX_ZOOM)
		_handover()
		queue_redraw()
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampf(zoom * 1.25, 1.0, MAX_ZOOM)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampf(zoom / 1.25, 1.0, MAX_ZOOM)
			_handover()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# On a satellite, either button assigns it. Nothing else on the map
			# lives a hundred kilometres up, so there is nothing for a right
			# click up there to be confused with — and reaching for right click
			# is what anybody does when they want to target something.
			if _pick_satellite(mb.position):
				return
			_lay_mark(mb)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# SHIFT or CTRL and click plants an objective marker, and the same
			# on a satellite assigns it to the ASAT launchers. Shift on the
			# *right* button belongs to the weapons -- the extra warheads on a
			# MIRV bus -- so the left one is free for it, and shift and click is
			# what anybody reaches for to drop a waypoint.
			if (mb.shift_pressed or mb.ctrl_pressed or mb.meta_pressed) and mb.pressed:
				if _pick_satellite(mb.position):
					return
				var vp0 := get_viewport_rect().size
				var ppm0 := minf(vp0.x, vp0.y) * 0.86 * zoom / (HALF * 2.0)
				var org0 := vp0 * 0.5
				# Through the ball on the globe, a straight scale on the chart:
				# the same as a fire mission. Worked out as if the map were flat
				# whatever it was showing, the marker landed hundreds of
				# kilometres from the click whenever the planet was up.
				var w: Vector2 = _globe_point(mb.position) if globe \
					else centre + (mb.position - org0) / ppm0
				if is_inf(w.x):
					return
				var at := Vector3(w.x, Sim.height_at(w.x, w.y), w.y)
				if Sim.objective != Vector3.INF \
						and Vector2(Sim.objective.x - at.x,
							Sim.objective.z - at.z).length() < 40.0 / ppm0 * 12.0:
					Sim.clear_objective()
				else:
					Sim.set_objective(at)
				return
			if pick_cb.is_valid() and mb.pressed and not globe:
				var vp1 := get_viewport_rect().size
				var ppm1 := minf(vp1.x, vp1.y) * 0.86 * zoom / (HALF * 2.0)
				var w1: Vector2 = centre + (mb.position - vp1 * 0.5) / ppm1
				var cb := pick_cb
				var what := pick_label
				var from := pick_from
				var at1 := Vector3(w1.x, Sim.height_at(w1.x, w1.y), w1.y)
				cancel_pick()
				pick_life = null
				cb.call(at1)
				if pick_cb.is_valid():
					# a second click is wanted: this one is the start of a line
					pick_from = at1
				else:
					# Leave the mark where it was put and the map up for a
					# moment. Closing on the click itself showed nothing: no
					# way to tell where it had gone, or that it had gone.
					# For as long as what it was laid for is still coming, and
					# no longer. Every mark stayed half a minute whatever it
					# was: a bomb that landed in five seconds left its cross
					# on the map for another twenty-five, and by the third
					# call the chart was a litter of strikes long over.
					var mark := {"at": at1, "from": from, "label": what,
						"until": Time.get_ticks_msec() + 30000}
					if pick_life is float or pick_life is int:
						mark["until"] = Time.get_ticks_msec() + int(float(pick_life) * 1000.0)
					elif pick_life is Node:
						mark["node"] = pick_life
						mark["until"] = Time.get_ticks_msec() + 240000
					pick_marks.append(mark)
					pick_life = null
					_close_tok += 1
					var tok := _close_tok
					get_tree().create_timer(0.7).timeout.connect(func():
						if tok == _close_tok and visible and not pick_cb.is_valid():
							toggle())
				queue_redraw()
				return
			_drag = mb.pressed
			if mb.pressed:
				follow = false
	elif e is InputEventMouseMotion and pick_cb.is_valid() and not _drag:
		queue_redraw()
	elif e is InputEventMouseMotion and _drag:
		var vp := get_viewport_rect().size
		var px_per_m := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
		centre -= (e as InputEventMouseMotion).relative / px_per_m

func _process(d: float) -> void:
	# A bake finishing is the one thing that changes the picture without
	# anything on screen having moved, so it is collected here rather than only
	# where the globe is drawn.
	if globe and visible and Sim.native != null:
		globe_view._collect_patch()
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
## A right click on the ground, chart or globe alike: a fire mission for the
## artillery piece you are in, an aiming point for the strategic round in the
## boat you are in. Split out of the chart's handler, because the map has been
## the globe for a while and the globe never reached it -- right click on the
## planet picked satellites and did nothing else, so a fire mission could not be
## laid from the map at all.
func _lay_mark(mb: InputEventMouseButton) -> void:
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
	# A rough click near a contact means the contact. Thirty pixels' worth of
	# ground, but never less than two kilometres -- zoomed right in, a miss by
	# a ship's length should still take her -- nor more than eight, or zoomed
	# out a click anywhere in a sea area would grab whatever was in it.
	if hit == null:
		var m_per_px: float = Sim.PLANET_R / maxf(minf(vp.x, vp.y) * 0.42 * globe_zoom, 1.0) \
			if globe else 1.0 / maxf(scl, 1e-6)
		hit = _contact_by_ground(at, clampf(30.0 * m_per_px, 2000.0, 8000.0))
	if tank != null and is_instance_valid(tank) and tank.is_indirect():
		var n_rv: int = tank.warheads()
		var laid: int = tank.warhead_marks().size()
		# A unit clicked on is kept as the unit, so the warhead given it is
		# locked on and follows it -- it used to be stored as the spot it was
		# standing on, and the log said only how far away that spot was.
		var mk: Variant = at
		if hit != null:
			mk = hit
		var km: float = tank.global_position.distance_to(Tank.mark_at(mk)) * 0.001
		if n_rv > 0:
			# One click, one warhead. A round that carries several can be
			# given several marks -- which is what "independently targetable"
			# means -- and they used to need shift: a plain right click put
			# the whole load on one mark, which read as every warhead going
			# down at once. Now each click lays the next, RV1 to RVn; past the
			# last one the next click starts the mission over, and ctrl clears
			# it. Warheads left without a mark of their own share the ones
			# there are.
			if mb.ctrl_pressed or mb.meta_pressed:
				tank.mirv_marks.clear()
				tank.map_lock = null
				tank.map_target = Vector3.INF
				Sim.report("warhead marks cleared", Sim.Ev.INFO)
				return
			if laid >= n_rv or laid == 0:
				if laid >= n_rv:
					Sim.report("all %d warheads were marked — starting a new fire mission" % n_rv,
						Sim.Ev.INFO)
				tank.mirv_marks.clear()
				tank.map_lock = hit
				tank.map_target = Tank.mark_at(mk)
			else:
				tank.mirv_marks.append(mk)
			var rv: int = tank.warhead_marks().size()
			var next := ("  — right click for RV%d of %d" % [rv + 1, n_rv]) if rv < n_rv \
				else "  — all %d marked" % n_rv
			if hit != null:
				var also := PackedStringArray()
				var marks: Array = tank.warhead_marks()
				for k in marks.size() - 1:
					# is_same, not ==: a ground mark is a Vector3, and comparing
					# one with an object is an error rather than false
					if is_same(marks[k], hit):
						also.append("RV%d" % (k + 1))
				Sim.report("RV%d locked on %s — %.1f km%s%s" % [rv,
					Sim.label_of(hit), km,
					("  (same unit as %s)" % ", ".join(also)) if not also.is_empty() else "",
					next], Sim.Ev.GOOD)
			else:
				Sim.report("RV%d on a ground point — %.1f km%s" % [rv, km, next], Sim.Ev.INFO)
			return
		tank.mirv_marks.clear()
		tank.map_lock = hit
		tank.map_target = Tank.mark_at(mk)
		if hit != null:
			Sim.report("locked: %s at %.1f km" % [Sim.label_of(hit), km], Sim.Ev.GOOD)
			return
		Sim.report("fire mission: %.1f km" % km, Sim.Ev.INFO)
	elif ship != null and is_instance_valid(ship) and ship.can_launch():
		strategic_mark = at
		ship.strategic_aim = at
		Sim.report("aiming point set: %.0f km" % (
			ship.global_position.distance_to(at) * 0.001), Sim.Ev.INFO)

## The nearest contact on the map to a point on the ground, within `reach`
## metres: hostiles first, since that is what a fire mission is for, and never
## one of your own.
func _contact_by_ground(at: Vector3, reach: float) -> Node:
	var best: Node = null
	var bd := INF
	for c in _contacts:
		var nv: Variant = c["n"]
		if not is_instance_valid(nv) or not bool(c["hostile"]):
			continue
		var p: Vector3 = (nv as Node3D).global_position
		var d: float = Vector2(p.x - at.x, p.z - at.z).length()
		if d < reach and d < bd:
			bd = d
			best = nv
	return best

## One warhead's mark on the map: a red ring and the unit's name when it is
## locked on something, an amber ring when it is a patch of ground. Only the
## warheads past the first are drawn when the first is the fire mission's own
## mark, which has its own cross already.
func _rv_mark(at: Vector2, wi: int, mk: Variant) -> void:
	var unit: Node3D = Tank.mark_unit(mk)
	if unit != null:
		var rc := Color(1.0, 0.36, 0.30)
		draw_arc(at, 11.0, 0, TAU, 18, rc, 2.0)
		draw_arc(at, 15.0, 0, TAU, 18, Color(rc.r, rc.g, rc.b, 0.45), 1.0)
		_label(at + Vector2(16, -6), "RV%d  %s" % [wi + 1, Sim.label_of(unit).to_upper()], rc, 11)
		_label(at + Vector2(16, 8), "LOCKED", rc, 10)
	else:
		var wc := Color(1.0, 0.75, 0.25)
		draw_arc(at, 9.0, 0, TAU, 16, wc, 1.4)
		draw_line(at - Vector2(0, 9), at + Vector2(0, 9), wc, 1.2)
		_label(at + Vector2(12, 4), "RV%d  GROUND" % (wi + 1), Color(1.0, 0.8, 0.4), 11)

## The rest of the load the weapon camera's round came off a bus with, and
## what each warhead is going for.
##
## The map followed the one round the camera was riding, so once a bus opened
## it showed a single warhead and nothing of the other seven. Every one is
## marked now, with a line to its target: a red ring on a unit it has locked, a
## small cross on a patch of ground. `proj` turns a world point into a screen
## point, with z > 0 when it is on the visible side.
func _draw_salvo(riding: Node3D, proj: Callable) -> void:
	if not (riding is Missile):
		return
	var rm: Missile = riding
	var pack: Array = rm.salvo()
	var amber := Color(1.0, 0.85, 0.35)
	var red := Color(1.0, 0.40, 0.32)
	var faint := Color(1.0, 0.85, 0.35, 0.6)
	var units := 0
	var drawn := {}
	for i in pack.size():
		var m: Missile = pack[i]
		var unit: bool = m.locked_on_unit()
		if unit:
			units += 1
		var q: Vector3 = proj.call(m.global_position, true)
		var tq := Vector3(0, 0, -1)
		if is_instance_valid(m.target):
			tq = proj.call(m.target.global_position, false)
		if q.z > 0.0 and tq.z > 0.0:
			draw_line(Vector2(q.x, q.y), Vector2(tq.x, tq.y),
				Color(red.r, red.g, red.b, 0.5) if unit else Color(faint.r, faint.g, faint.b, 0.35),
				1.0)
		var on_sheet: bool = Rect2(Vector2(-200, -200),
			get_viewport_rect().size + Vector2(400, 400)).has_point(Vector2(q.x, q.y))
		if q.z > 0.0 and m != rm and on_sheet:
			var c := Vector2(q.x, q.y)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4),
				c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), amber)
		if tq.z <= 0.0:
			continue
		var key: int = m.target.get_instance_id()
		if drawn.has(key):
			continue
		drawn[key] = true
		var t2 := Vector2(tq.x, tq.y)
		if unit:
			draw_arc(t2, 7.0, 0.0, TAU, 16, red, 1.6)
		else:
			draw_line(t2 + Vector2(-3.5, -3.5), t2 + Vector2(3.5, 3.5), faint, 1.2)
			draw_line(t2 + Vector2(-3.5, 3.5), t2 + Vector2(3.5, -3.5), faint, 1.2)
	if pack.size() > 1:
		var rq: Vector3 = proj.call(rm.global_position, true)
		if rq.z > 0.0:
			_label(Vector2(rq.x, rq.y) + Vector2(14, 8), "x%d  %d locked" % [
				pack.size(), units], red if units > 0 else amber, 11)

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
	return _toggle_sat_target(hit)

## A satellite clicked on the map: held as the orbital target, or let go if it
## already was. False when the click found none.
func _toggle_sat_target(hit: Node) -> bool:
	if hit == null:
		return false
	sat_target = null if sat_target == hit else hit
	Sim.sat_target = sat_target
	Sim.report("orbital target: %s" % (String(hit.call("display_name"))
		if sat_target != null else "released"), Sim.Ev.INFO)
	return true

func _w2s(p: Vector2, org: Vector2, px_per_m: float) -> Vector2:
	return org + (p - centre) * px_per_m

## Everything called down that has not arrived yet: where it will land and
## how long it has to go, and anything still flying in, where it is now and
## where it is going. The mark laid for it shows where it was asked for; this
## shows it coming.
func _draw_inbound(org: Vector2, ppm: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var arena: Variant = world.get("cqb")
	if arena == null or not is_instance_valid(arena) or not (arena is CqbMatch):
		return
	var now: float = float(Time.get_ticks_msec()) * 0.001
	var blink: float = 0.55 + 0.45 * absf(sin(now * 6.0))
	var warm := Color(1.0, 0.58, 0.18)
	# What is on the chart. Something coming in from outside it -- a strike
	# run starting kilometres out, a battery firing from beyond the town -- is
	# shown at the edge, pointing at where it is, so it is seen coming rather
	# than appearing at the moment it arrives.
	var vp := get_viewport_rect().size
	var box := Rect2(Vector2(28.0, 78.0), vp - Vector2(56.0, 170.0))
	for it in (arena as CqbMatch).streaks.inbound():
		var d: Dictionary = it
		var at: Vector3 = d["at"]
		var q := _w2s(Vector2(at.x, at.z), org, ppm)
		var eta: float = float(d.get("eta", -1.0))
		var lab: String = String(d.get("label", ""))
		var kind := String(d["kind"])
		if not box.has_point(q) and kind in ["plane", "missile", "shell", "gun"]:
			_edge_arrow(q, box, kind, lab, eta, warm)
			# still draw the track across the chart, so you see where a strike
			# run or a warhead is coming in along before it gets here
			if kind not in ["plane", "missile"] or not (d.has("from") and d.has("to")):
				continue
		match kind:
			"bombs":
				var r: float = maxf(float(d["r"]) * ppm, 3.0)
				for p in (d["pts"] as Array):
					var pq := _w2s(Vector2((p as Vector3).x, (p as Vector3).z), org, ppm)
					draw_arc(pq, r, 0.0, TAU, 20, Color(warm.r, warm.g, warm.b, 0.45 * blink), 1.4)
					draw_circle(pq, 2.0, warm)
				_label(q + Vector2(r + 6.0, 4.0), "%s  %.1fs" % [lab, maxf(eta, 0.0)], warm, 13)
			"nuke":
				var nc := Color(1.0, 0.25, 0.15, blink)
				var rr: float = maxf(float(d["r"]) * ppm, 6.0)
				draw_arc(q, rr, 0.0, TAU, 48, nc, 2.4)
				draw_arc(q, rr * 0.55, 0.0, TAU, 40, Color(nc.r, nc.g, nc.b, 0.5), 1.4)
				draw_circle(q, 3.0, nc)
				_label(q + Vector2(8.0, -rr - 6.0), "%s  %ds" % [lab, int(ceil(maxf(eta, 0.0)))],
					Color(1.0, 0.4, 0.3), 14)
			"plane", "missile", "drone":
				var col := Color(1.0, 0.86, 0.4) if String(d["kind"]) != "drone" \
					else Color(0.5, 0.9, 1.0)
				if d.has("from") and d.has("to"):
					var a0: Vector3 = d["from"]
					var a1: Vector3 = d["to"]
					draw_dashed_line(_w2s(Vector2(a0.x, a0.z), org, ppm),
						_w2s(Vector2(a1.x, a1.z), org, ppm), Color(col.r, col.g, col.b, 0.7), 2.0, 8.0)
				elif d.has("to"):
					var a2: Vector3 = d["to"]
					draw_dashed_line(q, _w2s(Vector2(a2.x, a2.z), org, ppm),
						Color(col.r, col.g, col.b, 0.6), 1.4, 6.0)
				if d.has("mid"):
					var mid: Vector3 = d["mid"]
					draw_arc(_w2s(Vector2(mid.x, mid.z), org, ppm), float(d["r"]) * ppm,
						0.0, TAU, 40, Color(col.r, col.g, col.b, 0.3), 1.2)
				var hv: Variant = d.get("head", Vector3.ZERO)
				var h3: Vector3 = hv if hv is Vector3 else Vector3.ZERO
				var hd := Vector2(h3.x, h3.z)
				hd = hd.normalized() if hd.length() > 0.01 else Vector2(0, -1)
				var sd := Vector2(-hd.y, hd.x)
				var s: float = 7.0 if String(d["kind"]) != "missile" else 5.0
				draw_colored_polygon(PackedVector2Array([q + hd * s * 1.4, q - hd * s + sd * s,
					q - hd * s * 0.4, q - hd * s - sd * s]), col)
				if lab != "":
					var txt := lab
					if eta > 0.0:
						txt += "  %ds" % int(ceil(eta))
					_label(q + Vector2(10.0, -8.0), txt, col, 12)
			"falling":
				draw_circle(q, 2.2, warm)
			"shell":
				# a round in the air: a dot, and a short tail back along where
				# it has come from
				var hv2: Variant = d.get("head", Vector3.ZERO)
				var h2: Vector3 = hv2 if hv2 is Vector3 else Vector3.ZERO
				var hd2 := Vector2(h2.x, h2.z)
				if hd2.length() > 0.01:
					draw_line(q, q - hd2.normalized() * 9.0, Color(warm.r, warm.g, warm.b, 0.55), 1.4)
				draw_circle(q, 2.6, warm)
			"gun":
				var gc := Color(1.0, 0.86, 0.4)
				draw_rect(Rect2(q - Vector2(4.5, 4.5), Vector2(9.0, 9.0)), gc, false, 1.6)
				draw_circle(q, 1.6, gc)
				if lab != "":
					_label(q + Vector2(9.0, -6.0), lab, gc, 12)
			"area":
				# a strip of ground: smoke laid along a line, or burning
				var tint: Color = d.get("tint", Color(0.8, 0.8, 0.8))
				var f0: Vector3 = d["from"]
				var f1: Vector3 = d["to"]
				var p0 := _w2s(Vector2(f0.x, f0.z), org, ppm)
				var p1 := _w2s(Vector2(f1.x, f1.z), org, ppm)
				var wpx: float = maxf(12.0 * ppm, 4.0)
				draw_line(p0, p1, Color(tint.r, tint.g, tint.b, 0.35), wpx)
				if p0.distance_to(p1) < 1.0:
					draw_circle(p0, wpx * 0.5, Color(tint.r, tint.g, tint.b, 0.35))
				_label(q + Vector2(8.0, -wpx * 0.5 - 4.0), lab, tint, 12)
			"unit":
				var uc := Color(0.5, 0.9, 1.0)
				draw_circle(q, 3.0, uc)
				draw_arc(q, 5.0, 0.0, TAU, 12, uc, 1.0)
				if lab != "":
					_label(q + Vector2(7.0, -5.0), lab, uc, 11)
			"mark":
				var mc := Color(1.0, 0.7, 0.3, blink)
				draw_arc(q, maxf(float(d["r"]) * ppm, 6.0), 0.0, TAU, 24, mc, 1.6)
				_label(q + Vector2(10.0, 14.0), lab, mc, 12)

## Something inbound that is off the chart, drawn on its edge: an arrow
## pointing out at it, and what it is and how long it has, or how far off.
func _edge_arrow(q: Vector2, box: Rect2, kind: String, lab: String, eta: float,
		warm: Color) -> void:
	var c: Vector2 = box.get_center()
	var dv: Vector2 = q - c
	if dv.length() < 0.001:
		return
	var dn: Vector2 = dv.normalized()
	# where the line out from the middle leaves the box
	var tx: float = INF if absf(dn.x) < 1e-6 else ((box.size.x * 0.5) / absf(dn.x))
	var ty: float = INF if absf(dn.y) < 1e-6 else ((box.size.y * 0.5) / absf(dn.y))
	var e: Vector2 = c + dn * minf(tx, ty)
	var col: Color = warm if kind == "shell" else Color(1.0, 0.86, 0.4)
	var sd := Vector2(-dn.y, dn.x)
	draw_colored_polygon(PackedVector2Array([e, e - dn * 12.0 + sd * 6.0, e - dn * 12.0 - sd * 6.0]), col)
	if kind == "shell":
		return
	var txt := lab if lab != "" else kind.to_upper()
	if eta > 0.0:
		txt += "  %ds" % int(ceil(eta))
	# inside the arrow, so it does not run off the screen with it
	var at_l: Vector2 = e - dn * 22.0 + Vector2(-4.0 * float(txt.length()) * (0.5 + 0.5 * dn.x), 4.0)
	_label(at_l, txt, col, 12)

func _draw() -> void:
	if globe:
		globe_view._draw_globe()
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
	for r in Sim.roads.ROADS:
		draw_line(_w2s(r[0], org, ppm), _w2s(r[1], org, ppm), Color(0.55, 0.5, 0.42, 0.8), 1.6)

	# Close in, the buildings themselves. The sheet underneath is a picture
	# of the country at two metres a texel at best; at the scale of a street
	# it is a smear, and a map of a street fight has to show the streets.
	if ppm > 0.35:
		var half_w: Vector2 = vp * 0.5 / ppm
		for f in Obstacles.footprints(centre - half_w, centre + half_w):
			var fc: Vector2 = f[0]
			var fh: Vector2 = f[1]
			# Less than a pixel across is not a shape: a fence post at this
			# scale is four corners on top of one another, and handing that to
			# the polygon fill made it fail to triangulate and say so, every
			# frame the map was open.
			if minf(fh.x, fh.y) * 2.0 * ppm < 1.0:
				continue
			var fy: float = f[2]
			var ax := Vector2(cos(fy), -sin(fy)) * fh.x
			var az := Vector2(sin(fy), cos(fy)) * fh.y
			var tall: float = f[3]
			var fcol := Color(0.62, 0.66, 0.72, 0.92) if tall > 4.0 else Color(0.50, 0.46, 0.38, 0.9)
			draw_colored_polygon(PackedVector2Array([_w2s(fc - ax - az, org, ppm),
				_w2s(fc + ax - az, org, ppm), _w2s(fc + ax + az, org, ppm),
				_w2s(fc - ax + az, org, ppm)]), fcol)
		# a scale, because at this zoom nothing else says how far anything is
		var bar: float = 50.0 * ppm
		draw_line(Vector2(24, vp.y - 60), Vector2(24 + bar, vp.y - 60), Color(1, 1, 1, 0.9), 2.0)
		_label(Vector2(24, vp.y - 78), "50 m", Color(1, 1, 1, 0.9), 12)
	# where support has been called down, for as long as it matters
	var now_ms := Time.get_ticks_msec()
	var mkc := Color(1.0, 0.35, 0.2)
	for i in range(pick_marks.size() - 1, -1, -1):
		var pm: Dictionary = pick_marks[i]
		# its own thing gone: a moment more, to see where it went in
		if pm.has("node") and not is_instance_valid(pm["node"]):
			pm.erase("node")
			pm["until"] = mini(int(pm["until"]), now_ms + 1500)
		if now_ms > int(pm["until"]):
			pick_marks.remove_at(i)
			continue
		var at_m: Vector3 = pm["at"]
		var q := _w2s(Vector2(at_m.x, at_m.z), org, ppm)
		var fr: Vector3 = pm["from"]
		if fr != Vector3.INF:
			var q0 := _w2s(Vector2(fr.x, fr.z), org, ppm)
			draw_line(q0, q, mkc, 3.0)
			draw_arc(q0, 7.0, 0.0, TAU, 16, mkc, 2.0)
		draw_arc(q, 12.0, 0.0, TAU, 24, mkc, 2.2)
		draw_line(q - Vector2(18, 0), q + Vector2(18, 0), mkc, 1.6)
		draw_line(q - Vector2(0, 18), q + Vector2(0, 18), mkc, 1.6)
		_label(q + Vector2(16, -20), String(pm["label"]).get_slice(" — ", 0), mkc, 13)
	_draw_inbound(org, ppm)
	if pick_cb.is_valid():
		# the cursor is the aiming mark while a pick is waited for
		var mq := get_local_mouse_position()
		var pc := Color(1.0, 0.9, 0.3)
		if pick_from != Vector3.INF:
			var p0 := _w2s(Vector2(pick_from.x, pick_from.z), org, ppm)
			draw_arc(p0, 7.0, 0.0, TAU, 16, pc, 2.0)
			draw_line(p0, mq, pc, 2.5)
			_label(mq + Vector2(16, 8), "%d m" % int(p0.distance_to(mq) / ppm), pc, 13)
		draw_arc(mq, 14.0, 0.0, TAU, 24, pc, 2.0)
		draw_line(mq - Vector2(22, 0), mq - Vector2(6, 0), pc, 1.6)
		draw_line(mq + Vector2(6, 0), mq + Vector2(22, 0), pc, 1.6)
		draw_line(mq - Vector2(0, 22), mq - Vector2(0, 6), pc, 1.6)
		draw_line(mq + Vector2(0, 6), mq + Vector2(0, 22), pc, 1.6)
		draw_rect(Rect2(0, 0, vp.x, 44), Color(0.5, 0.1, 0.05, 0.85))
		_label(Vector2(24, 12), "%s — click where you want it.  M cancels." % pick_label,
			Color(1, 0.95, 0.85), 18)

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
			_draw_salvo(riding, func(w: Vector3, _air: bool) -> Vector3:
				var f := _w2s(Vector2(w.x, w.z), org, ppm)
				return Vector3(f.x, f.y, 1.0))
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
		var rvs: Array = tank.warhead_marks()
		for wi in rvs.size():
			var wm: Vector3 = Tank.mark_at(rvs[wi])
			var wp := _w2s(Vector2(wm.x, wm.z), org, ppm)
			_rv_mark(wp, wi, rvs[wi])
		_label(Vector2(24, vp.y - 120), "right click to lay a fire mission"
			+ ("  ·  each click marks the next warhead (%d of %d)  ·  ctrl+right click clears" % [
				rvs.size(), tank.warheads()] if tank.warheads() > 0 else ""),
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
		"wheel zoom (out far enough for the planet)   drag to pan   shift+click sets an objective (again to clear)   click a satellite to target it   M to close",
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

## Put the objective where a click on the globe meets the ground -- or take it
## away, when the click is on the one already there.
func _objective_at(click: Vector2) -> void:
	var w := _globe_point(click)
	if is_inf(w.x):
		return
	if Sim.objective != Vector3.INF:
		var vp := get_viewport_rect().size
		var q := globe_view._globe_at(Vector2(Sim.objective.x, Sim.objective.z), vp * 0.5,
			minf(vp.x, vp.y) * 0.42 * globe_zoom, globe_view._globe_basis())
		if q.z > 0.0 and Vector2(q.x, q.y).distance_to(click) < 14.0:
			Sim.clear_objective()
			queue_redraw()
			return
	Sim.set_objective(Vector3(w.x, Sim.height_at(w.x, w.y), w.y))
	queue_redraw()

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
	var dir: Vector3 = (globe_view._globe_basis().inverse() * v).normalized()
	return Sim.dir_to_chart(dir)

## `_contact_near`, through the globe's projection.
func _contact_near_globe(at: Vector2) -> Node:
	var vp := get_viewport_rect().size
	var org := vp * 0.5
	var rad: float = minf(vp.x, vp.y) * 0.42 * globe_zoom
	var b := globe_view._globe_basis()
	var best: Node = null
	var bd := 26.0
	for c in _contacts:
		var nv: Variant = c["n"]
		if not is_instance_valid(nv):
			continue
		var n: Node3D = nv
		var p: Vector3 = n.global_position
		var lift: float = 1.0 + maxf(Sim.altitude(p), 0.0) / Sim.PLANET_R
		var q := globe_view._globe_at(Vector2(p.x, p.z), org, rad, b, lift)
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
func _pick_satellite_globe(at: Vector2) -> bool:
	var vp := get_viewport_rect().size
	var org := vp * 0.5
	var rad: float = minf(vp.x, vp.y) * 0.42 * globe_zoom
	var b := globe_view._globe_basis()
	var hit: Node = null
	var best := 22.0
	for sat in get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		var q: Vector3 = (sat as Node3D).global_position
		var lift: float = 1.0 + Sim.altitude(q) / Sim.PLANET_R
		var p := globe_view._globe_at(Vector2(q.x, q.z), org, rad, b, lift)
		if p.z <= 0.0:
			continue
		var d: float = Vector2(p.x, p.y).distance_to(at)
		if d < best:
			best = d
			hit = sat
	return _toggle_sat_target(hit)

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

## See `MapGlobe.toggle_globe`.
func toggle_globe() -> void:
	globe_view.toggle_globe()
