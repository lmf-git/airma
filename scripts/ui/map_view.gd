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
var _font: Font
var _drag := false
var _mouse_was := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
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
	map_stats = {"res": RES, "ms": Time.get_ticks_msec() - t0, "land": land,
		"sea": sea}

func toggle() -> void:
	visible = not visible
	set_process(visible)
	# the map is useless without a pointer, and driving or walking captures it
	if visible:
		_mouse_was = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if aircraft != null and is_instance_valid(aircraft):
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
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampf(zoom * 1.25, 1.0, 400.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampf(zoom / 1.25, 1.0, 400.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# right click lays a fire mission for an artillery piece, and the
			# aiming point for a strategic launch when you are in the boat that
			# carries one. There was no path at all for the latter: the map
			# only ever spoke to a tank, and `_strategic_strike` asked the map
			# for a `target_point` it did not have — so aiming the round on the
			# map silently did nothing and the only way to send it was the pod.
			var vp := get_viewport_rect().size
			var org := vp * 0.5
			var scl := minf(vp.x, vp.y) * 0.86 * zoom / (HALF * 2.0)
			var w := centre + (mb.position - org) / scl
			var at := Vector3(w.x, Sim.height_at(w.x, w.y), w.y)
			# Clicked on something rather than somewhere? Then it is a lock, and
			# the round guides onto the unit instead of onto the patch of ground
			# the unit happened to be standing on when you pressed the button.
			var hit := _contact_near(mb.position, org, scl)
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
				# On a satellite? Then this is an orbital assignment, not a
				# place on the ground.
				var vpS := get_viewport_rect().size
				var ppmS := minf(vpS.x, vpS.y) * 0.86 * zoom / (HALF * 2.0)
				var orgS := vpS * 0.5
				var hit: Node = null
				var best := 18.0
				for sat2 in get_tree().get_nodes_in_group("satellites"):
					if not is_instance_valid(sat2) or not (sat2 is Node3D):
						continue
					var q: Vector3 = (sat2 as Node3D).global_position
					var d2: float = _w2s(Vector2(q.x, q.z), orgS, ppmS).distance_to(
						mb.position)
					if d2 < best:
						best = d2
						hit = sat2
				if hit != null:
					sat_target = hit if sat_target != hit else null
					Sim.sat_target = sat_target
					Sim.report("orbital target: %s" % (
						hit.call("display_name") if sat_target != null
						else "released"), Sim.Ev.INFO)
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
	if follow and aircraft != null and is_instance_valid(aircraft):
		centre = Vector2(aircraft.global_position.x, aircraft.global_position.z)
	# Twice a second is plenty for a picture, and working out who can see what
	# is a line of sight march per pair.
	_contact_t -= d
	if _contact_t <= 0.0:
		_contact_t = DETECT_EVERY
		_refresh_contacts()
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
		if not is_instance_valid(n) or n == aircraft:
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
	if aircraft != null and is_instance_valid(aircraft):
		var p := _w2s(Vector2(aircraft.global_position.x, aircraft.global_position.z), org, ppm)
		var fwd: Vector3 = -aircraft.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 11.0, p - dir * 6.0 + side * 6.0,
			p - dir * 6.0 - side * 6.0]), Color(0.4, 1.0, 0.5))
		_label(Vector2(24, vp.y - 96), "POS  %+.1f km E   %+.1f km N   ALT %d ft" % [
			aircraft.global_position.x * 0.001, -aircraft.global_position.z * 0.001,
			int(aircraft.global_position.y * 3.28084)], Color(0.7, 1.0, 0.8))

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
		"wheel zoom   drag to pan   ctrl+click sets an objective or picks a satellite   M to close",
		Color(0.6, 0.7, 0.8), 14)
	# north arrow
	var na := Vector2(vp.x - 60.0, 70.0)
	draw_line(na + Vector2(0, 18), na - Vector2(0, 18), Color(0.9, 0.95, 1.0), 2.0)
	draw_colored_polygon(PackedVector2Array([na - Vector2(0, 22), na + Vector2(-6, -10),
		na + Vector2(6, -10)]), Color(0.9, 0.95, 1.0))
	_label(na + Vector2(-5, 36), "N", Color(0.9, 0.95, 1.0))

func _label(at: Vector2, t: String, col: Color, pt := 13) -> void:
	draw_string(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, pt, col)
