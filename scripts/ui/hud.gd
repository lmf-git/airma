class_name HUD
extends Control
## World-referenced head-up display: the pitch ladder, flight-path marker and
## target boxes are unprojected through the live camera, so they stay glued to
## the world in every view.

const GREEN := Color(0.24, 1.0, 0.42)
const DIM := Color(0.30, 1.0, 0.48, 0.70)
const AMBER := Color(1.0, 0.78, 0.22)
const RED := Color(1.0, 0.32, 0.28)
## The laser's own colour, for marks the laser is actually on.
const LASER := Color(1.0, 0.45, 0.35)
const WHITE := Color(0.92, 0.96, 1.0)
const PANEL_NAMES := ["off", "sensor", "radar", "minimap"]

var aircraft: Aircraft = null
var _ccip_p := Vector3.INF
var _ccip_t := 0
var flight_page := true          # false from an outside camera: see world.gd
var walker: Node = null
var carrier: Carrier = null
## The launch vehicle, while it is crewed.
var rocket: LaunchVehicle = null
## The targeting pod, for the mark on the main view where it is looking.
var pod: SensorPod = null
var mode = null
var tank = null
var ship = null
var cam: Camera3D = null
var base: Airbase = null
var log_lines: Array = []
var show_help := true
var _t := 0.0
var _font: Font
## A real head-up display only covers twenty odd degrees of the windscreen.
## Symbology is clipped to that box so it sits inside the cockpit combiner
## instead of sprawling across the whole screen.
const HUD_HALF_ANGLE := deg_to_rad(11.5)
var _hud_c := Vector2.ZERO
var _hud_r := 0.0
var _hud_clip := false

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Sim.mission_event.connect(_on_event)
	# The key card draws itself, on its own schedule. A child, so it comes out
	# over the symbology the way it did when it was drawn last.
	_card = KeyCard.new()
	_card.name = "KeyCard"
	_card.font = _font
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

func _on_event(text: String, kind: int) -> void:
	log_lines.push_front({"t": text, "k": kind, "age": 0.0})
	if log_lines.size() > 6:
		log_lines.resize(6)

## The world, as the HUD needs to see it, fetched a few times a second instead
## of five times a frame.
##
## Five separate panels walked `get_nodes_in_group("hittable")` in `_draw`, and
## `_draw` runs every frame: on a world of five thousand nodes that is five
## fresh arrays and five full walks, sixty times a second, for a picture that
## cannot change meaningfully between one frame and the next. It was the largest
## single script cost in the game after the terrain.
const CONTACT_EVERY := 0.1
var _seen: Array = []
var _seen_zones: Array = []
var _seen_t := 0.0
## What each contact *is*, settled when the list is built.
##
## Whether a node answers `is_alive` and whether it is in `no_lock` are facts
## about its class, not about this frame -- and every panel asked the engine
## both questions about every contact, every frame. `has_method` and
## `is_in_group` are string lookups into the engine; four loops over the
## hittables at seventy-nine frames a second is tens of thousands of them.
const SEEN_MORTAL := 1
const SEEN_NO_LOCK := 2
var _seen_what := PackedByteArray()

func _refresh_seen(delta: float) -> void:
	_seen_t -= delta
	if _seen_t > 0.0 and not _seen.is_empty():
		return
	_seen_t = CONTACT_EVERY
	_mode_state = mode.hud_state() if (mode != null and is_instance_valid(mode)) else {}
	_seen = get_tree().get_nodes_in_group("hittable")
	_seen_zones = get_tree().get_nodes_in_group("zones")
	_seen_what.resize(_seen.size())
	for k in _seen.size():
		var n: Node = _seen[k]
		_seen_what[k] = (SEEN_MORTAL if n.has_method("is_alive") else 0) \
			| (SEEN_NO_LOCK if n.is_in_group("no_lock") else 0)
	_refresh_masking()

## Whether the terrain is in the way of each contact.
##
## A sight line is a march of up to forty-eight height samples, and the scope
## wants one per contact. Asked every frame -- even batched into a single call
## across every core -- that was 0.23 ms of a 12.8 ms frame, the largest single
## thing left in the head-up display. Whether a ridge is between you and a
## bandit does not change in a hundredth of a second, so it is settled here at
## ten hertz with the rest of the list. At five hundred knots the eye moves
## twenty-five metres between refreshes, against a march that steps a hundred
## and eighty.
var _seen_clear := PackedByteArray()
var _seen_los := PackedByteArray()

func _refresh_masking() -> void:
	if _seen.is_empty():
		_seen_clear = PackedByteArray()
		return
	var eye := _scope_origin() + Vector3(0, 4, 0)
	var from := PackedVector3Array()
	var to := PackedVector3Array()
	from.resize(_seen.size())
	to.resize(_seen.size())
	for k in _seen.size():
		from[k] = eye
		to[k] = (_seen[k] as Node3D).global_position + Vector3(0, 4, 0)
	_seen_clear = Sim.lines_of_sight(from, to, 250.0)
	# ...and the same question as the boxes on the glass ask it: from the
	# aeroplane itself, to the contact itself. It was asked there once per
	# contact per frame, one crossing of the extension boundary each -- the
	# largest single cost in the display, 0.8 ms of a frame in a battle -- for
	# an answer that changes no faster than the scope's does.
	if is_instance_valid(aircraft):
		var own: Vector3 = aircraft.global_position
		for k in _seen.size():
			from[k] = own
			to[k] = (_seen[k] as Node3D).global_position
		_seen_los = Sim.lines_of_sight(from, to)
	else:
		_seen_los = PackedByteArray()

func _process(delta: float) -> void:
	var _pp := Sim.prof_at()
	_refresh_seen(delta)
	_tick(delta)
	Sim.prof_end(&"hud.process", _pp)

func _tick(delta: float) -> void:
	_t += delta
	for l in log_lines:
		l["age"] += delta
	_refresh_help()
	queue_redraw()

## Caching the shaped text was tried and buys nothing.
##
## `draw_string` looked like it must be re-laying out every string on every
## call, and the head-up display makes about ninety of those a frame, half of
## them labels that never change. Holding the finished layout in a `TextLine`
## and drawing that instead measured 1.500 ms against 1.477 -- no change at all,
## which says the text server already keeps what it needs. Left written down so
## it is not tried again.
func _txt(pos: Vector2, s: String, pt := 15, col := GREEN, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(_font, pos, s, align, w, pt, col)

func _box(r: Rect2, col := GREEN, width := 1.0) -> void:
	draw_rect(r, col, false, width)

func _draw() -> void:
	# `.total`, because it wraps every other hud tag. The breakdown adds up
	# every tag that is not marked as containing others, and named `hud.draw`
	# this one was counted twice over -- once itself and once in its children --
	# which put a millisecond and a half of script on the report that was not
	# there.
	var _ph := Sim.prof_at()
	_draw_all()
	Sim.prof_end(&"hud.total", _ph)

## Seconds left to get back inside the fight, or below zero when inside it.
var oob_left := -1.0

func _draw_oob() -> void:
	if oob_left < 0.0:
		return
	var vp := get_viewport_rect().size
	var flash: float = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.006))
	draw_rect(Rect2(0, vp.y * 0.30, vp.x, 70.0), Color(0.25, 0.0, 0.0, 0.45))
	_txt(Vector2(0, vp.y * 0.30 + 30.0), "OUT OF BOUNDS — RETURN TO THE FIGHT", 26,
		Color(1.0, 0.35, 0.3, flash), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_txt(Vector2(0, vp.y * 0.30 + 58.0), "%d" % int(ceil(oob_left)), 22,
		Color(1.0, 0.85, 0.8, flash), HORIZONTAL_ALIGNMENT_CENTER, vp.x)

func _draw_all() -> void:
	_draw_oob()
	# The objective marker belongs on every page too, and before anything
	# returns: the whole point of planting one on the map is that you can see it
	# from the cockpit, the chase camera, a driver's seat and a bridge.
	var _p12 := Sim.prof_at()
	_draw_objective()
	_draw_salvo()
	Sim.prof_end(&"hud.objective", _p12)
	# The key card belongs on every page. It was drawn at the end of the
	# aeroplane one, and every other page returns before it gets there — so F2
	# did nothing at all on a bridge, in a driver's seat or on foot, and the
	# only place the keys appeared was the event log.
	if rocket != null and is_instance_valid(rocket):
		_draw_rocket()
		return
	if carrier != null and is_instance_valid(carrier):
		_draw_conn()
		return
	if ship != null and is_instance_valid(ship):
		_draw_bridge()
		return
	if tank != null and is_instance_valid(tank):
		_draw_driver()
		return
	if walker != null and is_instance_valid(walker):
		_draw_on_foot()
		return
	if aircraft == null or not is_instance_valid(aircraft) or cam == null:
		return
	if not flight_page:
		# outside the aeroplane: no glass in front of you, no symbology on it,
		# but warnings and the event log still belong on screen
		var vpo := get_viewport_rect().size
		_draw_log(vpo)
		if ("msg_t" in aircraft) and aircraft.msg_t > 0.0:
			_txt(Vector2(0, vpo.y - 176.0), String(aircraft.msg).to_upper(), 19, WHITE,
				HORIZONTAL_ALIGNMENT_CENTER, vpo.x)
		return
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	var alive := aircraft.alive

	var _p13 := Sim.prof_at()
	_setup_hud_box()
	if alive:
		if _hud_clip:
			_draw_hud_glass()
		Sim.prof_end(&"hud.glass", _p13)
		var _p0 := Sim.prof_at()
		_draw_ladder()
		Sim.prof_end(&"hud.ladder", _p0)
		var _p1 := Sim.prof_at()
		_draw_fpm()
		Sim.prof_end(&"hud.fpm", _p1)
		var _p2 := Sim.prof_at()
		_draw_targets()
		_draw_spot_target()
		_draw_sensor_mark()
		Sim.prof_end(&"hud.targets", _p2)
		var _p3 := Sim.prof_at()
		_draw_bomb_cue()
		Sim.prof_end(&"hud.bomb_cue", _p3)
	var _p4 := Sim.prof_at()
	_draw_left(vp)
	Sim.prof_end(&"hud.left", _p4)
	var _p5 := Sim.prof_at()
	_draw_right(vp)
	Sim.prof_end(&"hud.right", _p5)
	var _p6 := Sim.prof_at()
	_draw_heading(vp)
	Sim.prof_end(&"hud.heading", _p6)
	var _p7 := Sim.prof_at()
	_draw_status(vp)
	Sim.prof_end(&"hud.status", _p7)
	var _p8 := Sim.prof_at()
	_draw_panels(vp)
	Sim.prof_end(&"hud.panels", _p8)
	var _p9 := Sim.prof_at()
	_draw_landing(vp)
	_draw_service(vp)
	Sim.prof_end(&"hud.landing", _p9)
	var _p10 := Sim.prof_at()
	_draw_warnings(vp, c)
	Sim.prof_end(&"hud.warnings", _p10)
	var _p11 := Sim.prof_at()
	_draw_log(vp)
	Sim.prof_end(&"hud.log", _p11)
	if mode != null and is_instance_valid(mode):
		var _p14 := Sim.prof_at()
		_draw_mode(vp)
		Sim.prof_end(&"hud.mode", _p14)


## Driver and gunner readout.
## Bridge page: what the officer of the watch needs and nothing else.
## Contacts painted onto the world from a hull's own camera. The aeroplane's
## version reads `jet` and projects through the head-up display's camera and
## clip circle, neither of which a ship has -- so from a bridge or a chase view
## there was nothing on screen at all: no boxes, no labels, no way to tell a
## friend from an enemy except by shape.
## The callsign of whoever is flying, driving or walking this thing, if it
## belongs to a player at all.
func _callsign_of(n: Node) -> String:
	var net: NetLink = Sim.net
	if net == null or not net.active:
		return ""
	for d in [net.ghosts, net.veh_ghosts, net.foot_ghosts]:
		for pid in (d as Dictionary):
			if (d as Dictionary)[pid] == n:
				return net.name_of(int(pid))
	return ""

## Whether the screen is the weapon camera riding a round, rather than the
## view from the seat.
func riding_round() -> bool:
	if not is_instance_valid(cam) or not cam.current:
		return false
	var rv: Variant = cam.get("weapon_cam")
	return rv != null and is_instance_valid(rv)

## Riding a round on the weapon camera: the rest of its load and what each
## warhead is steering for.
##
## Once a bus opened, the camera went with one warhead and the picture said
## nothing about the other seven -- where they were, whether they had found
## anything, or which of the vehicles below was about to be hit. Each one is
## marked now, with a line to what it is going for: a red bracket and a name
## for a unit it has locked, a small cross for a patch of ground.
func _draw_salvo() -> void:
	if not is_instance_valid(cam) or not cam.current:
		return
	var rv: Variant = cam.get("weapon_cam")
	if rv == null or not is_instance_valid(rv) or not (rv is Missile):
		return
	var riding: Missile = rv
	var pack: Array = riding.salvo()
	var vp := get_viewport_rect().size
	var amber := Color(1.0, 0.82, 0.30)
	var red := Color(1.0, 0.36, 0.30)
	var faint := Color(1.0, 0.82, 0.30, 0.55)
	var units := 0
	var drawn := {}
	for i in pack.size():
		var m: Missile = pack[i]
		var mp: Vector3 = m.global_position
		var sp := Vector2.INF
		if not cam.is_position_behind(mp):
			sp = cam.unproject_position(mp)
			# a warhead flying in formation a few metres off the lens projects
			# to somewhere enormous, and a polygon out there is degenerate
			if not Rect2(Vector2(-200, -200), vp + Vector2(400, 400)).has_point(sp):
				sp = Vector2.INF
			elif m != riding:
				draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -5),
					sp + Vector2(5, 0), sp + Vector2(0, 5), sp + Vector2(-5, 0)]), amber)
				_txt(sp + Vector2(7, -5), str(i + 1), 11, amber)
		var unit: bool = m.locked_on_unit()
		if unit:
			units += 1
		if not is_instance_valid(m.target):
			continue
		var tp: Vector3 = m.target.global_position + Vector3(0, 2.0, 0)
		if cam.is_position_behind(tp):
			continue
		var tq: Vector2 = cam.unproject_position(tp)
		var col: Color = red if unit else faint
		if sp != Vector2.INF:
			draw_dashed_line(sp, tq, Color(col.r, col.g, col.b, 0.45),
				2.0 if m == riding else 1.0, 6.0)
		var key: int = m.target.get_instance_id()
		if drawn.has(key):
			continue
		drawn[key] = true
		var d: float = cam.global_position.distance_to(tp)
		if unit:
			var r: float = clampf(26000.0 / maxf(d, 1.0), 9.0, 34.0)
			var k: float = r * 0.45
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var cpt: Vector2 = tq + corner * r
				draw_line(cpt, cpt - Vector2(corner.x * k, 0), red, 2.0)
				draw_line(cpt, cpt - Vector2(0, corner.y * k), red, 2.0)
			_txt(tq + Vector2(r + 6, -r + 10), Sim.label_of(m.target).to_upper(), 12, red)
		else:
			draw_line(tq + Vector2(-5, -5), tq + Vector2(5, 5), faint, 1.4)
			draw_line(tq + Vector2(-5, 5), tq + Vector2(5, -5), faint, 1.4)
	# and a line about the lot of it, under the top edge
	var short := String(WeaponSpec.get_spec(riding.wid)["short"])
	var line := short
	if pack.size() > 1:
		line = "%s x%d — %d LOCKED ON UNITS, %d ON GROUND POINTS" % [
			short, pack.size(), units, pack.size() - units]
	elif riding.locked_on_unit():
		line = "%s — LOCKED ON %s" % [short, Sim.label_of(riding.target).to_upper()]
	if is_instance_valid(riding.target):
		var sp2: float = maxf(riding.vel.length(), 1.0)
		var to_go: float = riding.global_position.distance_to(riding.target.global_position)
		line += "   %.1f km  %d s" % [to_go * 0.001, int(to_go / sp2)]
	_txt(Vector2(0, 92.0), line, 16, amber if units == 0 else red,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x)

## The objective the player marked with shift and click on the map, drawn into
## whatever camera is live. Off screen it becomes an arrow at the edge pointing
## the way round, because a marker you cannot see is not much of a marker.
func _draw_objective() -> void:
	if Sim.objective == Vector3.INF:
		return
	var eye: Camera3D = _live_camera()
	if not is_instance_valid(eye):
		return
	var vp := get_viewport_rect().size
	var col := Color(1.0, 0.82, 0.25)
	var at: Vector3 = Sim.objective + Vector3(0, 12.0, 0)
	var from: Vector3 = eye.global_position
	var d: float = from.distance_to(at)
	var behind: bool = eye.is_position_behind(at)
	var p := eye.unproject_position(at) if not behind else Vector2.ZERO
	var on: bool = not behind and p.x > 8.0 and p.y > 8.0 \
		and p.x < vp.x - 8.0 and p.y < vp.y - 8.0
	if on:
		var r: float = clampf(2400.0 / maxf(d, 1.0), 9.0, 46.0)
		draw_arc(p, r, 0.0, TAU, 22, col, 2.0)
		draw_line(p + Vector2(-r - 7, 0), p + Vector2(-r + 3, 0), col, 1.6)
		draw_line(p + Vector2(r - 3, 0), p + Vector2(r + 7, 0), col, 1.6)
		draw_line(p + Vector2(0, -r - 7), p + Vector2(0, -r + 3), col, 1.6)
		_txt(p + Vector2(r + 8, 4), "OBJ %.1f km" % (d * 0.001), 13, col)
		return
	# Off the glass: an arrow on the edge, pointing round to it.
	var c := vp * 0.5
	var dir: Vector2 = (p - c) if not behind else Vector2.ZERO
	if behind or dir.length() < 1.0:
		# Behind the camera the projection is meaningless, so the bearing is
		# worked out in the world instead and turned into a screen direction.
		var rel: Vector3 = eye.global_transform.basis.inverse() * (at - from)
		dir = Vector2(rel.x, -rel.y)
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0, 1)
	dir = dir.normalized()
	var edge: Vector2 = c + dir * (minf(vp.x, vp.y) * 0.40)
	draw_line(edge, edge - dir.rotated(0.5) * 16.0, col, 2.0)
	draw_line(edge, edge - dir.rotated(-0.5) * 16.0, col, 2.0)
	_txt(edge - dir * 34.0 + Vector2(-24, 18), "OBJ %.1f km" % (d * 0.001), 12, col)

## Whichever camera the player is actually looking through.
func _live_camera() -> Camera3D:
	for c in [rocket, carrier, ship, tank]:
		if c != null and is_instance_valid(c) and "cam" in c:
			var cc: Camera3D = c.get("cam")
			if is_instance_valid(cc) and cc.current:
				return cc
	if is_instance_valid(cam) and cam.current:
		return cam
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null

func _draw_world_contacts(src: Node3D, eye_in: Camera3D) -> void:
	# Through whichever camera is actually on the screen. The pages hand in the
	# vehicle's own, and when the weapon camera takes the screen to ride a round
	# out of the launcher, the boxes went on being projected from the launcher:
	# they sat still on the glass while the world moved under them.
	var eye: Camera3D = _live_camera()
	if not is_instance_valid(eye):
		eye = eye_in
	if not is_instance_valid(src) or not is_instance_valid(eye):
		return
	var my_team: int = int(src.team) if ("team" in src) else -1
	# Held loosely first, then checked, then typed. Whatever the aeroplane was
	# tracking may have been destroyed since it picked it, and assigning a freed
	# instance into a typed variable is itself the error -- so it cannot be
	# caught after the assignment, only before it.
	var held: Node = null
	if "ai_target" in src:
		var raw: Variant = src.get("ai_target")
		if is_instance_valid(raw) and raw is Node:
			held = raw
	var reach: float = maxf(Sim.coverage(my_team), 26000.0)
	var vp := get_viewport_rect().size
	for k in _seen.size():
		var seen_k: Variant = _seen[k]
		if not is_instance_valid(seen_k):
			continue
		var n: Node = seen_k
		if not is_instance_valid(n) or n == src or not (n is Node3D):
			continue
		if _seen_what[k] & SEEN_NO_LOCK != 0:
			continue
		if _seen_what[k] & SEEN_MORTAL != 0 and not n.is_alive():
			continue
		var p: Vector3 = (n as Node3D).global_position
		var d: float = src.global_position.distance_to(p)
		if d > reach or eye.is_position_behind(p):
			continue
		# aim at the waterline of a ship and the box sits in the sea; lift it
		# to something like the middle of the thing
		var lift := 6.0
		if n.has_method("mast_height"):
			lift = float(n.call("mast_height")) * 0.5
		# A ridge is a ridge from a bridge too. The scope and the aeroplane both
		# hide what they cannot see; without the same test here a hull in a
		# fjord labelled contacts straight through the headland.
		var from_eye: Vector3 = src.global_position + Vector3(0,
			float(src.call("mast_height")) if src.has_method("mast_height") else 4.0, 0)
		if d > 2000.0 and not Sim.line_of_sight(from_eye, p + Vector3(0, 4, 0), 250.0):
			continue
		var sp: Vector2 = eye.unproject_position(p + Vector3(0, lift, 0))
		if sp.x < 6.0 or sp.y < 6.0 or sp.x > vp.x - 6.0 or sp.y > vp.y - 6.0:
			continue
		var hostile: bool = ("team" in n) and int(n.team) != my_team
		var col := RED if hostile else Color(0.42, 0.78, 1.0)
		if n == held:
			col = AMBER
		var r: float = clampf(2600.0 / maxf(d, 1.0), 7.0, 44.0)
		_box(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), col, 1.5)
		if n == held:
			draw_arc(sp, r + 8.0, 0.0, TAU, 22, col, 1.6)
		var nm := str(n.name)
		if n.has_method("display_name"):
			nm = String(n.call("display_name"))
		# Another player is a person, not an airframe. Labelled by type, every
		# remote in the session read as "F-16" and there was no way to tell who
		# you were looking at or who you were about to shoot.
		var who := _callsign_of(n)
		if who != "":
			nm = who
		_txt(sp + Vector2(r + 6, -2), nm.left(18), 13, col)
		_txt(sp + Vector2(r + 6, 14), "%.1f km" % (d * 0.001), 12, col)

## The carrier's bridge. She is not a `Ship` and she has no armament at all, so
## without a page of her own the HUD carried on drawing the aeroplane's -- gun,
## stores, weapon select and all -- for a ship that cannot fire anything.
## The capsule's panel. Everything on it is a figure the vehicle works out
## from where it is and how fast it is going: there is no instrument here that
## is told the answer.
func _draw_rocket() -> void:
	var vp := get_viewport_rect().size
	var lines: PackedStringArray = rocket.readout()
	var y: float = vp.y - 40.0 - float(lines.size()) * 24.0
	for i in lines.size():
		_txt(Vector2(26, y + float(i) * 24.0), lines[i], 17 if i == 0 else 16,
			GREEN if i != 4 else Color(0.6, 0.9, 1.0))
	_txt(Vector2(26, vp.y - 22.0),
		"SHIFT/CTRL throttle  X cut  W/S pitch  Q/E yaw  A/D roll  T attitude hold  SPACE stage  H autopilot  , . warp  M map  U out",
		13, Color(0.6, 0.75, 0.85))
	_draw_log(vp)

func _draw_conn() -> void:
	var vp := get_viewport_rect().size
	var g := GREEN
	_draw_world_contacts(carrier, carrier.cam if is_instance_valid(carrier.cam) else cam)
	_txt(Vector2(26, vp.y - 176.0), "FLEET CARRIER", 17, g)
	_txt(Vector2(26, vp.y - 150.0), "SPEED %.1f kts" % (carrier.speed * 1.94384), 16, g)
	_txt(Vector2(26, vp.y - 126.0), "ENGINES %+d%%" % int(carrier.telegraph * 100.0), 16, g)
	_txt(Vector2(26, vp.y - 102.0), "HELM %s" % (
		"AMIDSHIPS" if absf(carrier.helm) < 0.08
		else ("STARBOARD %d" % int(absf(carrier.helm) * 100.0) if carrier.helm > 0.0
		else "PORT %d" % int(absf(carrier.helm) * 100.0))), 16, g)
	_txt(Vector2(26, vp.y - 78.0), "HEADING %03d" % int(
		wrapf(rad_to_deg(carrier.heading), 0.0, 360.0)), 16, g)
	_txt(Vector2(26, vp.y - 54.0), "DECK CLEAR — U TO HAND OVER", 14,
		Color(0.6, 0.75, 0.85))
	_draw_log(vp)

func _draw_bridge() -> void:
	var vp := get_viewport_rect().size
	var g := GREEN
	# what is out there, drawn on the sea itself
	_draw_world_contacts(ship, ship.cam if is_instance_valid(ship.cam) else cam)
	_txt(Vector2(26, vp.y - 176.0), ship.display_name().to_upper(), 17, g)
	_txt(Vector2(26, vp.y - 150.0), "SPEED %.1f kts" % (ship.speed * 1.94384), 16, g)
	_txt(Vector2(26, vp.y - 126.0), "ENGINES %+d%%" % int(ship.telegraph * 100.0), 16, g)
	_txt(Vector2(26, vp.y - 102.0), "HELM %s" % (
		"AMIDSHIPS" if absf(ship.helm) < 0.08
		else ("STARBOARD %d" % int(absf(ship.helm) * 100.0) if ship.helm > 0.0
		else "PORT %d" % int(absf(ship.helm) * 100.0))), 16, g)
	_txt(Vector2(26, vp.y - 78.0), "HEADING %03d" % int(
		fmod(rad_to_deg(ship.heading) + 360.0, 360.0)), 16, g)
	_txt(Vector2(26, vp.y - 54.0), "HULL %d" % int(maxf(ship.health, 0.0)), 16,
		RED if ship.health < float(Ship.KINDS[ship.kind]["hp"]) * 0.35 else g)
	# The armament line, always — it used to be inside a `has_gun()` test, so a
	# submarine, whose only weapon is its tubes, was told nothing at all about
	# what it had selected or whether it could fire it. The readiness shown is
	# the *selected* weapon's, not always the gun's.
	var state: String = ship.weapon_state()
	if ship.armed():
		_txt(Vector2(26, vp.y - 30.0), "%s  %s" % [ship.weapon_label(), state], 16,
			g if state == "READY" else AMBER)
	else:
		_txt(Vector2(26, vp.y - 30.0), "UNARMED", 16, Color(0.6, 0.75, 0.85))
	# and what it is laid on, which is the whole point of having a sensor
	if is_instance_valid(ship.ai_target):
		var td: float = ship.global_position.distance_to(ship.ai_target.global_position)
		_txt(Vector2(26, vp.y - 6.0), "LAID ON %s  %.1f km" % [
			Sim.label_of(ship.ai_target).to_upper(), td * 0.001], 15, AMBER)
	var c := vp * 0.5
	if not riding_round():
		draw_line(c - Vector2(22, 0), c - Vector2(6, 0), g, 1.6)
		draw_line(c + Vector2(6, 0), c + Vector2(22, 0), g, 1.6)
		draw_line(c - Vector2(0, 22), c - Vector2(0, 6), g, 1.6)
		draw_line(c + Vector2(0, 6), c + Vector2(0, 22), g, 1.6)
	# A warship has a mast full of antennas and every reason to want a scope.
	# The panel was written against the aeroplane and read `jet` for everything,
	# so a ship had none at all.
	_scope_src = ship
	_draw_radar_at(Vector2(vp.x - 200.0, vp.y - 190.0), 96.0)
	_scope_src = null
	_draw_log(vp)

func _draw_driver() -> void:
	var vp := get_viewport_rect().size
	# An air defence vehicle is a radar with rounds attached, and crewing one
	# gave you no radar picture at all: you were expected to find aircraft by
	# looking out of the hatch. Anything with a set of its own gets a scope.
	if is_instance_valid(tank) and tank.has_method("radar_range") \
			and float(tank.call("radar_range")) > 0.0:
		_scope_src = tank
		_draw_radar_at(Vector2(vp.x - 140.0, vp.y - 150.0), 104.0)
	# Through the camera that is actually rendering, the way the ship and the
	# carrier already do it. A tank has its own camera, and projecting the
	# contacts through the aeroplane's instead meant the markers were laid out
	# by a viewpoint that was not the one on screen -- so the moment freelook
	# swung the view they scattered.
	_draw_world_contacts(tank, tank.cam if is_instance_valid(tank.cam) else cam)
	var c := vp * 0.5
	var g := Color(0.55, 1.0, 0.62)
	# The sight is the vehicle's. Riding a round on the weapon camera the
	# screen is not looking down the barrel, and a crosshair in the middle of
	# it marks nothing.
	#
	# And only through the sight. From the camera behind the vehicle the middle
	# of the screen is not where the gun is laid -- the barrel is somewhere
	# below it and off to one side of the view -- so a cross drawn there was an
	# aiming mark for nothing in particular. G puts you on the sight.
	var sight: bool = not riding_round() and tank.gunner
	if sight:
		draw_line(c - Vector2(30, 0), c - Vector2(8, 0), g, 1.5)
		draw_line(c + Vector2(8, 0), c + Vector2(30, 0), g, 1.5)
		draw_line(c - Vector2(0, 30), c - Vector2(0, 8), g, 1.5)
		draw_line(c + Vector2(0, 8), c + Vector2(0, 30), g, 1.5)
	if tank.gunner and sight:
		draw_arc(c, 60.0, 0, TAU, 40, Color(g.r, g.g, g.b, 0.4), 1.2)
		for i in range(-4, 5):
			var y := c.y + i * 16.0
			draw_line(Vector2(c.x - 12, y), Vector2(c.x - 4, y), Color(g.r, g.g, g.b, 0.5), 1.0)
	_txt(Vector2(26, vp.y - 148.0), tank.display_name().to_upper(), 17, g)
	_txt(Vector2(26, vp.y - 122.0), "SPEED %d km/h" % int(absf(tank.speed) * 3.6), 16, GREEN)
	_txt(Vector2(26, vp.y - 98.0), "HULL %d" % int(maxf(tank.health, 0.0)), 16,
		RED if tank.health < 90.0 else GREEN)
	# A piece that is still traversing is not ready, whatever the loader says
	var lay_off: float = tank.lay_error() if tank.is_indirect() else 0.0
	var gun_state := "READY"
	var gun_col := GREEN
	if tank._gun_cd > 0.0:
		gun_state = "LOADING %.0f" % tank._gun_cd
		gun_col = AMBER
	elif lay_off > 0.03:
		gun_state = "LAYING %.0f deg" % rad_to_deg(lay_off)
		gun_col = AMBER
	_txt(Vector2(26, vp.y - 74.0), "%s %s" % [tank.weapon_label(), gun_state], 16, gun_col)
	if tank.is_indirect():
		var aim: Vector3 = tank.ground_aim()
		if tank.map_target != Vector3.INF:
			aim = tank.map_target
		if aim != Vector3.INF and tank.vclass() == "tel":
			# A launcher is not a gun. Asking for a ballistic solution at its
			# four hundred metre a second "muzzle velocity" fails at any real
			# range, so a Fattah aimed forty kilometres away — a fifth of what
			# the round can do — was reported out of range.
			var mid: Dictionary = WeaponSpec.get_spec(
				String(Tank.KINDS[tank.kind].get("missile", "kalibr")))
			var rng2: float = tank.global_position.distance_to(aim)
			var reach: float = float(mid.get("range", 100000.0))
			var armed_up: bool = tank.rounds_left > 0 and rng2 <= reach
			_txt(Vector2(26, vp.y - 196.0), "%s   %d ABOARD   MARK %.0f km of %.0f" % [
				String(mid.get("short", "MSL")), tank.rounds_left,
				rng2 * 0.001, reach * 0.001], 16,
				Color(0.8, 0.95, 1.0) if armed_up else AMBER)
			_txt(Vector2(26, vp.y - 172.0),
				"READY TO LAUNCH" if armed_up else (
					"NO ROUNDS" if tank.rounds_left <= 0 else "BEYOND THE ROUND'S REACH"),
				16, GREEN if armed_up else RED)
			# What each warhead has been given, above the mark: a unit it is
			# locked on, by name, or a patch of ground. A bus with marks laid
			# against three vehicles read only "MARK 72 km", which said nothing
			# about whether it would go for them.
			if tank.warheads() > 0:
				var rvs: Array = tank.warhead_marks()
				var y0: float = vp.y - 222.0
				if rvs.size() > 1 or (rvs.size() == 1 and Tank.mark_unit(rvs[0]) != null):
					for wi in rvs.size():
						var wi_r: int = rvs.size() - 1 - wi
						var u: Node3D = Tank.mark_unit(rvs[wi_r])
						var at: Vector3 = Tank.mark_at(rvs[wi_r])
						var km: float = tank.global_position.distance_to(at) * 0.001
						_txt(Vector2(26, y0 - float(wi) * 20.0),
							("RV%d  %s  LOCKED  %.1f km" % [wi_r + 1, Sim.label_of(u).to_upper(), km])
							if u != null else ("RV%d  GROUND POINT  %.1f km" % [wi_r + 1, km]),
							15, RED if u != null else AMBER)
					_txt(Vector2(26, y0 - float(rvs.size()) * 20.0),
						"%d WARHEADS — %d MARKED" % [tank.warheads(), rvs.size()], 14,
						Color(0.8, 0.95, 1.0))
		elif aim != Vector3.INF:
			var rng: float = tank.global_position.distance_to(aim)
			var sol: Dictionary = tank.fire_solution(aim, float(Tank.KINDS[tank.kind]["muzzle"]))
			if sol.is_empty():
				_txt(Vector2(26, vp.y - 172.0), "IMPACT %.1f km   OUT OF RANGE" % (rng * 0.001),
					16, RED)
			else:
				var bearing := fmod(rad_to_deg(tank.aim_yaw) + 360.0, 360.0)
				_txt(Vector2(26, vp.y - 196.0),
					"BEARING %03d   RANGE %.1f km%s" % [int(bearing), rng * 0.001,
					"   (map fire mission)" if tank.map_target != Vector3.INF else ""],
					16, Color(0.8, 0.95, 1.0))
				_txt(Vector2(26, vp.y - 172.0),
					"QE %.0f deg   CHARGE %d%%   TOF %.0f s" % [
					rad_to_deg(float(sol["elev"])),
					int(float(sol["charge"]) * 100.0), float(sol["tof"])], 16, GREEN)
		if not tank.last_solution.is_empty():
			_txt(Vector2(26, vp.y - 24.0),
				"LAST: %.1f km at %.0f deg, %d rounds, impact in %.0f s" % [
				float(tank.last_solution["range"]) * 0.001,
				float(tank.last_solution["elev"]), int(tank.last_solution["salvo"]),
				float(tank.last_solution.get("tof", 0.0))], 14, Color(0.7, 0.85, 0.95))
	_txt(Vector2(26, vp.y - 48.0),
		"W/S drive   A/D steer   X brake   SPACE fire   V coax   C sight   U out", 14,
		Color(0.85, 0.92, 1.0))
	_draw_log(vp)

## What a man on foot needs in front of him: where the rounds will go, what
## is left to send, and what is being done to him.
func _draw_on_foot() -> void:
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	var w: Walker = walker as Walker
	var g: Dictionary = w.gun_spec()
	var eye: Camera3D = w.cam

	# Whose side everyone is on. Uniforms do it up close; across a street in
	# bad light a chevron over your own people does it better.
	if is_instance_valid(eye) and eye.current:
		for n in get_tree().get_nodes_in_group("infantry"):
			var sd := n as Soldier
			if sd == null or sd.team != w.side or not sd.is_alive():
				continue
			var at: Vector3 = sd.global_position + Vector3(0, 2.05, 0)
			if eye.is_position_behind(at):
				continue
			var far: float = eye.global_position.distance_to(at)
			var sp: Vector2 = eye.unproject_position(at)
			# A man right at the camera plane projects to infinity, or to
			# nothing a triangle can be made of, and the fill says so.
			if not sp.is_finite() or absf(sp.x) > 1.0e5 or absf(sp.y) > 1.0e5 or far < 0.3:
				continue
			var a: float = clampf(1.15 - far / 160.0, 0.25, 0.9)
			var blue := Color(0.35, 0.72, 1.0, a)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(-5, -8), sp + Vector2(5, -8),
				sp + Vector2(0, 0)]), blue)
			if far < 40.0:
				_txt(Vector2(sp.x - 60.0, sp.y - 12.0), sd.callsign, 11, blue,
					HORIZONTAL_ALIGNMENT_CENTER, 120.0)

	if not (is_instance_valid(eye) and eye.current):
		# Riding a round on the weapon camera: his sight is not what is on
		# the screen, and a scope tube or a crosshair over the ride marks
		# nothing.
		pass
	elif w.glassing():
		# Field glasses: two tubes side by side, and what is outside them is
		# the inside of them. The outline is the two circles run together.
		var br: float = minf(vp.y * 0.46, vp.x * 0.31)
		var off: float = br * 0.5
		var cut: float = acos(off / br)
		var bdark := Color(0, 0, 0, 1)
		draw_rect(Rect2(0, 0, c.x - off - br, vp.y), bdark)
		draw_rect(Rect2(c.x + off + br, 0, vp.x - c.x - off - br, vp.y), bdark)
		var top := PackedVector2Array([Vector2(c.x - off - br, 0.0)])
		var bot := PackedVector2Array([Vector2(c.x - off - br, vp.y)])
		var rim := PackedVector2Array()
		for i in 25:
			var ta: float = lerpf(PI, TAU - cut, float(i) / 24.0)
			var q := Vector2(cos(ta), sin(ta)) * br
			top.append(c + Vector2(-off, 0) + q)
			bot.append(c + Vector2(-off, 0) + Vector2(q.x, -q.y))
		# from 1: the first point of this arc is the last of the other, and a
		# polygon with the same corner twice running does not triangulate
		for i in range(1, 25):
			var tb: float = lerpf(PI + cut, TAU, float(i) / 24.0)
			var q2 := Vector2(cos(tb), sin(tb)) * br
			top.append(c + Vector2(off, 0) + q2)
			bot.append(c + Vector2(off, 0) + Vector2(q2.x, -q2.y))
		rim.append_array(top.slice(1))
		var back := bot.slice(1)
		back.reverse()
		rim.append_array(back)
		rim.append(rim[0])
		top.append(Vector2(c.x + off + br, 0.0))
		bot.append(Vector2(c.x + off + br, vp.y))
		draw_colored_polygon(top, bdark)
		draw_colored_polygon(bot, bdark)
		draw_polyline(rim, bdark, 7.0, true)
		# a mil scale across the middle, and a short post under it
		var bink := Color(0.03, 0.03, 0.03, 0.9)
		draw_line(c + Vector2(-br * 0.5, 0), c + Vector2(-10, 0), bink, 1.4)
		draw_line(c + Vector2(10, 0), c + Vector2(br * 0.5, 0), bink, 1.4)
		draw_line(c + Vector2(0, 10), c + Vector2(0, br * 0.22), bink, 1.4)
		for k in range(-5, 6):
			if k == 0:
				continue
			var tx: float = float(k) * br * 0.1
			var th: float = 9.0 if k % 5 == 0 else 5.0
			draw_line(c + Vector2(tx, -th), c + Vector2(tx, th), bink, 1.2)
		var rng: float = w.glass_range()
		var brg: int = int(round(fposmod(-rad_to_deg(w.yaw), 360.0))) % 360
		_txt(Vector2(c.x - 150.0, c.y + br * 0.62), "%03d°   %s" % [brg,
			("%d m" % int(round(rng))) if rng >= 0.0 else "--- m"], 16,
			Color(0.75, 1.0, 0.8, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	elif w.scoped():
		# through the glass: everything outside the tube is the inside of it.
		# A 2x shows most of the screen, a prism a little less, a long scope
		# least of all.
		var reticle := String(g.get("reticle", "cross"))
		var r: float = vp.y * (0.49 if reticle == "ring" else (0.43 if reticle == "chevron" else 0.46))
		var dark := Color(0, 0, 0, 1)
		draw_rect(Rect2(0, 0, c.x - r, vp.y), dark)
		draw_rect(Rect2(c.x + r, 0, vp.x - c.x - r, vp.y), dark)
		# The corners between the circle and the square it sits in, as two
		# shapes: above the glass and below it. It was a strip per segment of
		# the rim down to the nearer edge, and the two strips that crossed the
		# middle went up on one side and down on the other -- a bow tie, which
		# the polygon fill cannot triangulate, and said so every frame.
		var above := PackedVector2Array([Vector2(c.x - r, 0.0)])
		var below := PackedVector2Array([Vector2(c.x + r, vp.y)])
		for i in 33:
			var ta: float = PI + PI * float(i) / 32.0
			above.append(c + Vector2(cos(ta), sin(ta)) * r)
			var tb: float = PI * float(i) / 32.0
			below.append(c + Vector2(cos(tb), sin(tb)) * r)
		above.append(Vector2(c.x + r, 0.0))
		below.append(Vector2(c.x - r, vp.y))
		draw_colored_polygon(above, dark)
		draw_colored_polygon(below, dark)
		draw_arc(c, r, 0, TAU, 64, Color(0, 0, 0, 1), 6.0)
		var ink := Color(0.03, 0.03, 0.03, 0.95)
		if reticle == "ring":
			# a lit ring and a dot, and nothing else in the way
			var lit := Color(1.0, 0.18, 0.10, 0.9)
			draw_arc(c, 34.0, 0, TAU, 48, lit, 1.6)
			draw_circle(c, 2.0, lit)
		elif reticle == "chevron":
			# the prism's chevron, lit amber, on a post, with the drop below it
			var amb := Color(1.0, 0.62, 0.12, 0.95)
			draw_line(c + Vector2(-9, 9), c, amb, 2.2)
			draw_line(c, c + Vector2(9, 9), amb, 2.2)
			draw_line(c + Vector2(0, 14), c + Vector2(0, r * 0.55), ink, 1.6)
			for k in range(1, 5):
				var y: float = 14.0 + k * 18.0
				var hw: float = 10.0 - k * 1.5
				draw_line(c + Vector2(-hw, y), c + Vector2(hw, y), ink, 1.2)
			draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.55, 0), ink, 1.4)
			draw_line(c + Vector2(r * 0.55, 0), c + Vector2(r, 0), ink, 1.4)
		else:
			draw_line(c + Vector2(-r, 0), c + Vector2(-14, 0), ink, 2.0)
			draw_line(c + Vector2(14, 0), c + Vector2(r, 0), ink, 2.0)
			draw_line(c + Vector2(0, 14), c + Vector2(0, r), ink, 2.0)
			draw_line(c + Vector2(0, -r), c + Vector2(0, -14), ink, 1.0)
			for k in range(1, 5):
				draw_line(c + Vector2(-5, k * 22.0), c + Vector2(5, k * 22.0), ink, 1.0)
			draw_circle(c, 1.4, Color(0.9, 0.1, 0.05, 0.9))
	else:
		# Four ticks that open as the weapon wanders. Through the sights in
		# first person the sights are the mark -- irons, a dot, a holo -- and
		# ticks painted over them only hid what they were laid on. It went only
		# for a red dot; now it fades as any weapon comes up to the eye. Over
		# the shoulder there is nothing to look through, so it stays.
		var fade: float = 1.0 if w.third else clampf(1.0 - w._ads * 1.6, 0.0, 1.0)
		if fade > 0.01:
			var px: float = vp.y * 0.5 / tan(deg_to_rad(eye.fov * 0.5)) if is_instance_valid(eye) else 600.0
			var gap: float = clampf(w.spread_now * px, 3.0, 90.0) + 3.0
			var col := Color(1, 1, 1, (0.82 if w.reloading <= 0.0 else 0.3) * fade)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + d * gap, c + d * (gap + 7.0), Color(0, 0, 0, 0.5 * fade), 3.0)
				draw_line(c + d * gap, c + d * (gap + 7.0), col, 1.4)
			draw_circle(c, 1.2, col)

	# The missile's sight: a ring the size of what the seeker can see, and
	# what the seeker is doing about it.
	#
	# All there was to aim a Stinger by was the tube itself and a box that
	# appeared on an aeroplane once the seeker had already found it -- nothing
	# said where to point to make that happen, how far along the lock was, or
	# that the thing would not fire without one. The ring is the seeker's
	# cone drawn to scale, so an aeroplane inside it is one it is looking at;
	# it fills round as the lock builds, and goes red and steady with it.
	var sam: bool = String(g.get("launcher", "")) == "sam"
	if sam and w._ads > 0.5 and is_instance_valid(eye) and eye.current:
		var px_s: float = vp.y * 0.5 / tan(deg_to_rad(eye.fov * 0.5))
		var ring: float = clampf(tan(deg_to_rad(w.SEEK_CONE)) * px_s, 40.0, vp.y * 0.46)
		var has: bool = is_instance_valid(w.lock_target)
		var got: bool = has and w.lock_t >= w.LOCK_TIME
		var sc := Color(0.55, 1.0, 0.62, 0.85)
		if got:
			sc = Color(1.0, 0.22, 0.16, 0.95)
		elif has:
			sc = Color(1.0, 0.74, 0.2, 0.95)
		var fade_s: float = clampf((w._ads - 0.5) * 4.0, 0.0, 1.0)
		sc.a *= fade_s
		var under := Color(0, 0, 0, 0.45 * fade_s)
		draw_arc(c, ring, 0.0, TAU, 72, under, 3.6)
		draw_arc(c, ring, 0.0, TAU, 72, sc, 1.6)
		# ticks at the quarters, and a pip to lay on it with
		for d4 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d4 * (ring - 10.0), c + d4 * (ring + 10.0), sc, 1.6)
			draw_line(c + d4 * 6.0, c + d4 * 16.0, sc, 1.4)
		draw_circle(c, 1.6, sc)
		if has and not got:
			# the lock, filling clockwise from the top
			var f: float = clampf(w.lock_t / w.LOCK_TIME, 0.0, 1.0)
			draw_arc(c, ring + 7.0, -PI * 0.5, -PI * 0.5 + TAU * f, 48, sc, 3.0)
		elif got:
			draw_arc(c, ring + 7.0, 0.0, TAU, 72, sc, 3.0)
		var word := "NO TARGET"
		if w.ammo <= 0:
			word = "TUBE EMPTY"
		elif got:
			word = "LOCKED — FIRE" if fmod(_t, 0.3) < 0.2 else ""
		elif has:
			word = "SEEKING"
		_txt(Vector2(c.x - 120.0, c.y + ring + 30.0), word, 16, sc,
			HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	# the seeker: a box on what it is looking at, closed when it has it
	if is_instance_valid(w.lock_target) and is_instance_valid(eye) \
			and not eye.is_position_behind(w.lock_target.global_position):
		var tgt_at: Vector3 = w.lock_target.global_position
		var lp: Vector2 = eye.unproject_position(tgt_at)
		var locked: bool = w.lock_t >= w.LOCK_TIME
		var lc := RED if locked else AMBER
		var lh: float = 26.0 if locked else lerpf(60.0, 26.0, clampf(w.lock_t / w.LOCK_TIME, 0.0, 1.0))
		if locked:
			# a diamond on it, and a line from the pip so it can be followed
			draw_polyline(PackedVector2Array([lp + Vector2(0, -lh), lp + Vector2(lh, 0),
				lp + Vector2(0, lh), lp + Vector2(-lh, 0), lp + Vector2(0, -lh)]), lc, 2.2)
			if lp.distance_to(c) > lh + 8.0:
				draw_line(c + (lp - c).normalized() * 8.0,
					lp - (lp - c).normalized() * lh, Color(lc.r, lc.g, lc.b, 0.5), 1.2)
		else:
			_box(Rect2(lp.x - lh, lp.y - lh, lh * 2.0, lh * 2.0), lc, 2.0)
		_txt(Vector2(lp.x - 80.0, lp.y + lh + 16.0), "%s  %.1f km" % [
			"LOCK" if locked else "SEEKING",
			eye.global_position.distance_to(tgt_at) * 0.001], 14, lc,
			HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	# a round of yours landing
	if w.hit_t > 0.0:
		var hc := Color(1.0, 0.25, 0.2, 1.0) if (w.kill_t > 0.0 or w.hit_head) else Color(1, 1, 1, 1)
		hc.a = clampf(w.hit_t / 0.22, 0.0, 1.0)
		var o: float = 7.0 + (1.0 - hc.a) * 4.0
		for d2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d2 * o, c + d2 * (o + 8.0), hc, 2.2)
	# and one of theirs: an arc on the side it came from
	if w.hurt_t > 0.0 and is_instance_valid(eye):
		var to: Vector3 = w.hurt_from - w.global_position
		var bearing: float = atan2(to.x, -to.z) + w.yaw
		var ha: float = clampf(w.hurt_t, 0.0, 1.0) * 0.85
		draw_arc(c, 120.0, bearing - PI * 0.5 - 0.32, bearing - PI * 0.5 + 0.32, 14,
			Color(1.0, 0.12, 0.08, ha), 7.0)
	# hurt: the edges of the world close in
	var blood: float = clampf(1.0 - w.health / 60.0, 0.0, 1.0)
	if blood > 0.0:
		var edge := Color(0.55, 0.0, 0.0, 0.34 * blood)
		var band: float = vp.y * 0.16
		draw_rect(Rect2(0, 0, vp.x, band), edge)
		draw_rect(Rect2(0, vp.y - band, vp.x, band), edge)
		draw_rect(Rect2(0, band, band, vp.y - band * 2.0), edge)
		draw_rect(Rect2(vp.x - band, band, band, vp.y - band * 2.0), edge)
	# pinned down: the edges go dark and the middle is all there is
	if w.suppression > 0.02:
		var dark := Color(0.0, 0.0, 0.0, 0.5 * w.suppression)
		var rim: float = vp.y * (0.10 + 0.14 * w.suppression)
		draw_rect(Rect2(0, 0, vp.x, rim), dark)
		draw_rect(Rect2(0, vp.y - rim, vp.x, rim), dark)
		draw_rect(Rect2(0, rim, rim, vp.y - rim * 2.0), dark)
		draw_rect(Rect2(vp.x - rim, rim, rim, vp.y - rim * 2.0), dark)
		draw_rect(Rect2(0, 0, vp.x, rim * 0.5), dark)
		draw_rect(Rect2(0, vp.y - rim * 0.5, vp.x, rim * 0.5), dark)
		draw_rect(Rect2(0, rim * 0.5, rim * 0.5, vp.y - rim), dark)
		draw_rect(Rect2(vp.x - rim * 0.5, rim * 0.5, rim * 0.5, vp.y - rim), dark)
	# a stun grenade: nothing but white, and then the world coming back
	var dazed: float = w.flash_left()
	if dazed > 0.0:
		var back: float = clampf(dazed / maxf(w.flash_span * 0.55, 0.4), 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 1.0, 1.0, back * back * (3.0 - 2.0 * back)))

	var p: String = w.prompt()
	if p != "":
		var bw := 420.0
		draw_rect(Rect2(c.x - bw * 0.5, c.y + 90.0, bw, 40.0), Color(0.02, 0.05, 0.07, 0.6), true)
		_box(Rect2(c.x - bw * 0.5, c.y + 90.0, bw, 40.0), AMBER, 1.4)
		_txt(Vector2(c.x - bw * 0.5, c.y + 116.0), p, 19, AMBER, HORIZONTAL_ALIGNMENT_CENTER, bw)

	# what is in the hands, bottom right where the weapon is
	var rel: bool = w.reloading > 0.0
	var low: bool = w.ammo <= maxi(int(float(g["mag"]) * 0.2), 1)
	_txt(Vector2(vp.x - 330.0, vp.y - 118.0), String(g["name"])
		+ ("  · SUPPRESSED" if w.is_quiet() else ""), 15,
		Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	_txt(Vector2(vp.x - 330.0, vp.y - 78.0), "%d" % w.ammo, 40,
		RED if (low or rel) else WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 220.0)
	_txt(Vector2(vp.x - 104.0, vp.y - 78.0), "/ %d" % w.spare, 20,
		Color(0.75, 0.8, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 90.0)
	if rel:
		_txt(Vector2(vp.x - 330.0, vp.y - 54.0), "RELOADING", 14, AMBER,
			HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	elif w.ammo == 0:
		_txt(Vector2(vp.x - 330.0, vp.y - 54.0), "EMPTY — R" if w.spare > 0 else "OUT — SWITCH WEAPON",
			14, RED, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	_txt(Vector2(vp.x - 330.0, vp.y - 32.0), "GRENADES %d   FLASH %d" % [w.grenades, w.flashes], 14,
		Color(0.75, 0.8, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	# the rack: which number is which
	for i in w.slots.size():
		var on: bool = i == w.slot
		_txt(Vector2(vp.x - 330.0, vp.y - 196.0 + i * 18.0), "%d  %s" % [i + 1,
			String(w.spec_of(int(w.slots[i]))["name"])], 13,
			AMBER if on else Color(0.55, 0.6, 0.65), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)

	var hb := 220.0
	var frac: float = clampf(w.health / 100.0, 0.0, 1.0)
	var hcol := RED if w.health < 40.0 else GREEN
	_box(Rect2(26, vp.y - 74.0, hb, 12), hcol, 1.2)
	draw_rect(Rect2(27, vp.y - 73.0, (hb - 2.0) * frac, 10), hcol)
	_txt(Vector2(26, vp.y - 82.0), "HEALTH %d" % int(maxf(w.health, 0.0)), 14, hcol)
	# wind: only worth drawing when some of it has been spent
	if w.stamina < 0.995:
		draw_rect(Rect2(27, vp.y - 59.0, (hb - 2.0) * w.stamina, 3),
			AMBER if w._winded else Color(0.85, 0.92, 1.0, 0.8))
	if w.arena != null and is_instance_valid(w.arena) and w.arena.has_method("hud_state"):
		var cs: Dictionary = w.arena.hud_state()
		_txt(Vector2(26, vp.y - 104.0), "KILLS %d   DEATHS %d   HEADSHOTS %d   STREAK %d" % [
			int(cs["kills"]), int(cs["deaths"]), int(cs["headshots"]), int(cs["streak"])], 14,
			Color(0.85, 0.92, 1.0))
		_draw_cqb_map(cs, Rect2(26.0, vp.y - 312.0, 184.0, 184.0))
		# the ladder: what a run of kills buys, and what is waiting to be spent
		var ly: float = vp.y - 300.0
		for k in cs["streaks"]:
			var have: int = int((cs["bank"] as Dictionary).get(k["id"], 0))
			var live: bool = String(k["id"]) == "uav" and float(cs["uav"]) > 0.0
			var txt: String = "%d  %s" % [int(k["key"]), String(k["name"])]
			if have > 0:
				txt += "  READY" + (" x%d" % have if have > 1 else "")
			elif live:
				txt += "  %ds" % int(float(cs["uav"]))
			else:
				txt += "  (%d kills)" % int(k["at"])
			_txt(Vector2(vp.x - 330.0, ly), txt, 13,
				GREEN if have > 0 else (AMBER if live else Color(0.5, 0.55, 0.6)),
				HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
			ly += 18.0
	_txt(Vector2(26, vp.y - 40.0),
		"F2 keys   SPACE vault/climb walls   C crouch   Z prone   F pick up   Q/E lean   G grenade   X flashbang   P view",
		13, Color(0.85, 0.92, 1.0))
	_draw_log(vp)
	if mode != null and is_instance_valid(mode):
		_draw_mode(vp)

## The street map in the corner of a street fight.
var _cqb_map: CqbMap = null

func _draw_cqb_map(cs: Dictionary, box: Rect2) -> void:
	if _cqb_map == null or not is_instance_valid(_cqb_map):
		_cqb_map = CqbMap.new()
		add_child(_cqb_map)
	_cqb_map.feed(cs, box)

## Him in the middle, north up, the buildings round him drawn from the
## buildings themselves, and everyone he is entitled to know about.
##
## It was the arena's own survey picture: a fixed square two hundred and sixty
## metres across, drawn the same whatever he did. Walk out of the arena and he
## walked off the map; stand at one end of it and half the map was what was
## behind him. Now it goes where he goes. The arena's edge is drawn on it, so
## where the fight is still reads.
##
## Its own control, so that it is clipped to its own box, and the buildings
## are one mesh rebuilt only when he has moved or the town has changed: a few
## hundred footprints filled one by one every frame was a few hundred polygon
## triangulations a frame.
class CqbMap extends Control:
	const SPAN := 300.0               # metres across the box
	const BLUE := Color(0.35, 0.72, 1.0)
	const RED := Color(1.0, 0.2, 0.15)
	var state: Dictionary = {}
	var fed_at := -10
	var _mesh: ArrayMesh = null
	var _mesh_at := Vector2(INF, INF)
	var _mesh_t := 0.0

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func feed(cs: Dictionary, box: Rect2) -> void:
		state = cs
		fed_at = Engine.get_process_frames()
		position = box.position
		size = box.size
		queue_redraw()

	func _process(delta: float) -> void:
		_mesh_t -= delta
		# not fed this frame: he is not on foot in a street fight any more
		if Engine.get_process_frames() - fed_at > 2 and not state.is_empty():
			state = {}
			queue_redraw()

	## Every footprint within reach, as triangles in metres from where he was.
	## Rebuilt every couple of seconds as well, because buildings come down.
	func _rebuild(me: Vector2) -> void:
		_mesh_at = me
		_mesh_t = 2.0
		_mesh = null
		var reach: float = SPAN * 0.75 + 30.0
		var verts := PackedVector2Array()
		var cols := PackedColorArray()
		for f in Obstacles.footprints(me - Vector2(reach, reach), me + Vector2(reach, reach), 3000):
			var fh: Vector2 = f[1]
			if minf(fh.x, fh.y) < 0.15:
				continue
			var fc: Vector2 = (f[0] as Vector2) - me
			var fy: float = f[2]
			var ax := Vector2(cos(fy), -sin(fy)) * fh.x
			var az := Vector2(sin(fy), cos(fy)) * fh.y
			var col := Color(0.62, 0.68, 0.74, 0.88) if float(f[3]) > 4.0 \
				else Color(0.52, 0.47, 0.38, 0.88)
			var p0: Vector2 = fc - ax - az
			var p1: Vector2 = fc + ax - az
			var p2: Vector2 = fc + ax + az
			var p3: Vector2 = fc - ax + az
			verts.append_array(PackedVector2Array([p0, p1, p2, p0, p2, p3]))
			for k in 6:
				cols.append(col)
		if verts.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_COLOR] = cols
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	func _draw() -> void:
		if state.is_empty():
			return
		var me: Vector2 = state.get("me_w", Vector2.ZERO)
		var ppm: float = size.x / SPAN
		var mid: Vector2 = size * 0.5
		var frame := Rect2(Vector2.ZERO, size)
		draw_rect(frame, Color(0.03, 0.06, 0.09, 0.62))
		if _mesh == null or _mesh_at.distance_to(me) > 12.0 or _mesh_t <= 0.0:
			_rebuild(me)
		if _mesh != null:
			draw_set_transform(mid + (_mesh_at - me) * ppm, 0.0, Vector2(ppm, ppm))
			draw_mesh(_mesh, null)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# where the fight is
		var area: Rect2 = state.get("area", Rect2())
		if area.size.x > 0.0:
			draw_rect(Rect2(mid + (area.position - me) * ppm, area.size * ppm),
				Color(1.0, 0.8, 0.3, 0.5), false, 1.2)
		if float(state.get("uav", 0.0)) > 0.0:
			# the sweep, so it is obvious why there is red on the map
			var sw: float = fmod(Time.get_ticks_msec() * 0.001, 2.0) / 2.0
			draw_line(Vector2(size.x * sw, 0.0), Vector2(size.x * sw, size.y),
				Color(1, 0.3, 0.2, 0.35), 2.0)
		for d in state.get("dots_w", []):
			var p: Vector2 = mid + ((d[0] as Vector2) - me) * ppm
			if frame.has_point(p):
				draw_circle(p, 3.2, BLUE if int(d[1]) == 0 else RED)
		var yaw: float = state.get("yaw", 0.0)
		var fw := Vector2(-sin(yaw), -cos(yaw))
		var rt := Vector2(-fw.y, fw.x)
		draw_colored_polygon(PackedVector2Array([mid + fw * 8.0, mid - fw * 5.0 + rt * 5.0,
			mid - fw * 2.0, mid - fw * 5.0 - rt * 5.0]), Color(1, 1, 1))
		draw_rect(frame, Color(0.6, 0.75, 0.9, 0.7), false, 1.2)
		# a scale, because nothing else on it says how far anything is
		var bar: float = 50.0 * ppm
		draw_line(Vector2(6, size.y - 8), Vector2(6 + bar, size.y - 8), Color(1, 1, 1, 0.8), 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(8 + bar, size.y - 4), "50 m",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))

## Work out where the combiner glass sits on screen this frame.
func _setup_hud_box() -> void:
	var vp := get_viewport_rect().size
	_hud_clip = false
	if cam == null or not is_instance_valid(cam) or aircraft == null:
		return
	# only in the cockpit: from outside, the symbology is an overlay
	if not (cam is ChaseCamera) or (cam as ChaseCamera).mode != ChaseCamera.Mode.COCKPIT:
		return
	var bore: Vector3 = cam.global_position + (-aircraft.global_transform.basis.z) * 900.0
	if cam.is_position_behind(bore):
		return
	_hud_c = cam.unproject_position(bore)
	_hud_r = tan(HUD_HALF_ANGLE) / tan(deg_to_rad(cam.fov * 0.5)) * (vp.y * 0.5)
	_hud_clip = true

func _in_hud(p: Vector2) -> bool:
	return not _hud_clip or (p - _hud_c).length() <= _hud_r

## Draw a line trimmed to the combiner. Segments entirely outside are dropped;
## one that crosses the edge is walked back to the boundary.
func _hud_line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	if not _hud_clip:
		draw_line(a, b, col, w)
		return
	var ina := _in_hud(a)
	var inb := _in_hud(b)
	if not ina and not inb:
		return
	if ina and inb:
		draw_line(a, b, col, w)
		return
	var inside := a if ina else b
	var outside := b if ina else a
	for i in 12:
		var mid := (inside + outside) * 0.5
		if _in_hud(mid):
			inside = mid
		else:
			outside = mid
	draw_line(a if ina else inside, inside if ina else b, col, w)

func _draw_hud_glass() -> void:
	var g := Color(GREEN.r, GREEN.g, GREEN.b, 0.16)
	draw_arc(_hud_c, _hud_r, 0, TAU, 48, g, 1.2)
	draw_line(_hud_c + Vector2(-_hud_r, 0), _hud_c + Vector2(-_hud_r + 8, 0), g, 1.2)
	draw_line(_hud_c + Vector2(_hud_r - 8, 0), _hud_c + Vector2(_hud_r, 0), g, 1.2)

# ---------------------------------------------------------------- pitch ladder
func _project(p: Vector3) -> Vector2:
	return cam.unproject_position(p)

## Where a bomb released now would land if nothing steered it. Recomputed a few
## times a second rather than every frame: it is a couple of hundred height
## field lookups and the answer does not move fast.
func _ccip() -> Vector3:
	if Time.get_ticks_msec() - _ccip_t < 120:
		return _ccip_p
	_ccip_t = Time.get_ticks_msec()
	var p: Vector3 = aircraft.global_position
	var v: Vector3 = aircraft.linear_velocity
	var dt := 0.12
	for i in 320:
		v.y -= 9.81 * dt
		p += v * dt
		if p.y <= Sim.height_at(p.x, p.z):
			_ccip_p = Vector3(p.x, Sim.height_at(p.x, p.z), p.z)
			return _ccip_p
	_ccip_p = Vector3.INF
	return _ccip_p

## Bombing cue: where the weapon is aimed, and where an unguided release would
## fall. Without it you are dropping on faith.
func _draw_bomb_cue() -> void:
	var w: String = aircraft.current_weapon()
	if w == "gun" or String(WeaponSpec.get_spec(w)["kind"]) != "bomb":
		return
	var aim := Vector3.INF
	var label := ""
	if aircraft.designated != Vector3.INF:
		aim = aircraft.designated
		label = "LASER"
	elif aircraft.target != null and is_instance_valid(aircraft.target):
		aim = (aircraft.target as Node3D).global_position
		label = Sim.label_of(aircraft.target).left(16).to_upper()
	if aim != Vector3.INF and cam.is_position_behind(aim) == false:
		var a := _project(aim)
		# a diamond on the designated point
		var r := 13.0
		_hud_line(a + Vector2(0, -r), a + Vector2(r, 0), AMBER, 2.0)
		_hud_line(a + Vector2(r, 0), a + Vector2(0, r), AMBER, 2.0)
		_hud_line(a + Vector2(0, r), a + Vector2(-r, 0), AMBER, 2.0)
		_hud_line(a + Vector2(-r, 0), a + Vector2(0, -r), AMBER, 2.0)
		_txt(a + Vector2(r + 5, 5), label, 13, AMBER)
		var d: float = aircraft.global_position.distance_to(aim)
		_txt(a + Vector2(r + 5, 21), "%.1f km" % (d * 0.001), 13, AMBER)
		# Whether the shot is actually on. A box and a range with nothing else
		# beside them reads as "cleared to release", and for an unpowered bomb
		# that is often a lie — it says the weapon failed when in truth the
		# aeroplane was never in a position to take the shot.
		var why := aircraft.shot_blocked(aircraft.current_weapon(), aircraft.target) \
			if is_instance_valid(aircraft.target) else ""
		if why != "":
			_txt(a + Vector2(r + 5, 37), why, 13, RED)
		elif aircraft.locked:
			_txt(a + Vector2(r + 5, 37), "LOCK", 13, GREEN)
	var fall := _ccip()
	if fall != Vector3.INF and not cam.is_position_behind(fall):
		var c := _project(fall)
		draw_arc(c, 9.0, 0.0, TAU, 18, GREEN, 1.8)
		_hud_line(c + Vector2(-14, 0), c + Vector2(-9, 0), GREEN, 1.8)
		_hud_line(c + Vector2(9, 0), c + Vector2(14, 0), GREEN, 1.8)
		if aim != Vector3.INF:
			var miss: float = Vector2(fall.x - aim.x, fall.z - aim.z).length()
			_txt(c + Vector2(12, -14), "CCIP %.0f m" % miss, 12,
				GREEN if miss < 120.0 else AMBER)

func _visible_pt(p: Vector3) -> bool:
	return not cam.is_position_behind(p)

func _draw_ladder() -> void:
	var b := aircraft.global_transform.basis
	var fwd := -b.z
	var head := Vector3(fwd.x, 0.0, fwd.z)
	if head.length_squared() < 0.001:
		head = Vector3(b.y.x, 0.0, b.y.z)
	head = head.normalized()
	var rt := head.cross(Vector3.UP).normalized() * -1.0
	var cp := cam.global_position
	const D := 900.0
	# Only the rungs that can be on the screen. All thirty-three were turned,
	# projected and tested every frame, and at any one moment two thirds of
	# them are above or below the glass. Measured from where the camera is
	# looking rather than where the nose is, so a freelook still finds them,
	# and wide enough for the tallest field of view the game uses.
	var look := -cam.global_transform.basis.z
	var look_deg: float = rad_to_deg(asin(clampf(look.y, -1.0, 1.0)))
	var span: float = cam.fov * 0.5 + 25.0
	var width3: float = get_viewport_rect().size.x * 3.0
	for p in range(-80, 85, 5):
		if absf(float(p) - look_deg) > span:
			continue
		var a := deg_to_rad(float(p))
		var d := head.rotated(rt, -a)
		var mid := cp + d * D
		var half := D * (0.10 if p % 10 == 0 else 0.055)
		var a1 := mid - rt * half
		var a2 := mid + rt * half
		if not (_visible_pt(a1) and _visible_pt(a2)):
			continue
		var s1 := _project(a1)
		var s2 := _project(a2)
		if s1.distance_to(s2) > width3:
			continue
		var col := DIM if p < 0 else GREEN
		var gap := 0.16 if p != 0 else 0.0
		var tick := (s2 - s1).normalized().orthogonal() * (10.0 if p > 0 else -10.0)
		if p == 0:
			_hud_line(s1, s2, GREEN, 2.2)
			_hud_line(s1 - (s2 - s1).normalized() * 60.0, s1, GREEN, 2.2)
			_hud_line(s2, s2 + (s2 - s1).normalized() * 60.0, GREEN, 2.2)
		else:
			var m1 := s1.lerp(s2, 0.5 - gap)
			var m2 := s1.lerp(s2, 0.5 + gap)
			if p > 0:
				_hud_line(s1, m1, col, 1.9)
				_hud_line(m2, s2, col, 1.9)
			else:
				_dashed(s1, m1, col)
				_dashed(m2, s2, col)
			_hud_line(s1, s1 + tick, col, 1.9)
			_hud_line(s2, s2 + tick, col, 1.9)
			var lbl := str(absi(p))
			if _in_hud(s1):
				_txt(s1 - Vector2(26, -5), lbl, 13, col)
			if _in_hud(s2):
				_txt(s2 + Vector2(6, 5), lbl, 13, col)

func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var n := 4
	for i in n:
		var t0 := float(i) / n
		var t1 := t0 + 0.55 / n
		_hud_line(a.lerp(b, t0), a.lerp(b, t1), col, 1.9)

func _draw_fpm() -> void:
	var v := aircraft.linear_velocity
	if v.length() < 12.0:
		return
	var p := cam.global_position + v.normalized() * 900.0
	if not _visible_pt(p):
		return
	var s := _project(p)
	if not _in_hud(s):
		return
	draw_arc(s, 9.0, 0, TAU, 20, GREEN, 2.2)
	draw_line(s + Vector2(9, 0), s + Vector2(20, 0), GREEN, 2.2)
	draw_line(s - Vector2(9, 0), s - Vector2(20, 0), GREEN, 2.2)
	draw_line(s - Vector2(0, 9), s - Vector2(0, 18), GREEN, 2.2)
	# gun cross / boresight
	var bs := cam.global_position + (-aircraft.global_transform.basis.z) * 900.0
	if _visible_pt(bs):
		var g := _project(bs)
		draw_line(g - Vector2(14, 0), g - Vector2(5, 0), WHITE, 1.4)
		draw_line(g + Vector2(5, 0), g + Vector2(14, 0), WHITE, 1.4)
		draw_line(g - Vector2(0, 14), g - Vector2(0, 5), WHITE, 1.4)

func _draw_targets() -> void:
	# Asked once, not once per contact: the reach walks three groups and the
	# rectangle is a call into the viewport, and neither depends on the contact.
	var reach: float = maxf(Sim.coverage(aircraft.team), 26000.0)
	var on_glass: Rect2 = get_viewport_rect().grow(-8.0)
	var own: Vector3 = aircraft.global_position
	var los_ok: bool = _seen_los.size() == _seen.size()
	for k in _seen.size():
		var seen_k: Variant = _seen[k]
		if not is_instance_valid(seen_k):
			continue
		var n: Node3D = seen_k
		if not is_instance_valid(n) or n == aircraft:
			continue
		if _seen_what[k] & SEEN_MORTAL != 0 and not n.is_alive():
			continue
		var hostile: bool = ("team" in n) and int(n.team) != aircraft.team
		var p: Vector3 = n.global_position
		if not _visible_pt(p):
			continue
		var d := own.distance_to(p)
		# Reach follows the radar setting rather than a fixed 26 km. Shipping
		# sits twenty-odd kilometres offshore and was falling off the edge of
		# the old limit, so a warship you had locked simply had no box on it.
		if d > reach:
			continue
		var s := _project(p)
		# Anywhere on the screen, not only inside the combiner glass: the radar
		# holds them whether or not they are in front of the HUD.
		if not on_glass.has_point(s):
			continue
		var r: float = clampf(900.0 / maxf(d, 1.0), 6.0, 40.0)
		# Coloured by what the interrogation actually came back with, not by
		# reading the other side's team off the object. Beyond transponder
		# range a contact is a return with no name against it — which is the
		# whole reason IFF exists and this had none.
		var id_code: int = Sim.iff(aircraft, n)
		var col := Color(0.4, 0.75, 1.0)
		if id_code == Sim.Iff.HOSTILE:
			col = RED
		elif id_code == Sim.Iff.UNKNOWN:
			col = Color(0.85, 0.85, 0.55)
		elif hostile:
			# it is on the other side but too far out to have answered
			col = Color(0.85, 0.85, 0.55)
		# A contact behind a ridge still shows -- the radar can see it -- but
		# the box goes dashed so you know you have no line of sight to it.
		var clear: bool = _seen_los[k] != 0 if los_ok else _los_clear(own, p)
		if n == aircraft.target:
			col = AMBER
			var q := r + 9.0
			draw_line(s + Vector2(-q, -q), s + Vector2(-q + 8, -q), col, 2.0)
			draw_line(s + Vector2(-q, -q), s + Vector2(-q, -q + 8), col, 2.0)
			draw_line(s + Vector2(q, q), s + Vector2(q - 8, q), col, 2.0)
			draw_line(s + Vector2(q, q), s + Vector2(q, q - 8), col, 2.0)
			_txt(s + Vector2(q + 6, -2), "%.1fkm" % (d * 0.001), 13, col)
			_txt(s + Vector2(q + 6, 14), "%d kt" % int(_kt(n)), 12, col)
			if aircraft.locked:
				# The same question the release cue asks. This one said LOCK
				# whenever the radar was holding something, whatever was on the
				# rail: a Maverick that cannot reach ten kilometres showed LOCK
				# on a target twenty away and went in the dirt.
				var stop := aircraft.shot_blocked(aircraft.current_weapon(), n)
				draw_arc(s, r + 16.0, 0, TAU, 24, col, 1.4)
				if stop == "":
					_txt(s + Vector2(q + 6, 30), "LOCK", 13, col)
				else:
					_txt(s + Vector2(q + 6, 30), stop, 13, RED)
			else:
				draw_arc(s, r + 16.0, _t * 3.0, _t * 3.0 + PI, 12, col, 1.2)
		else:
			if clear:
				_box(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), col, 1.4)
			else:
				_box_dashed(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), col, 1.4)
		if not clear:
			_txt(s + Vector2(r + 6, r + 4), "NO LOS", 11, col)

## The selected mark, when it is our own laser spot rather than a contact. It is
## not in the contact list -- it is not something to shoot at in its own right
## -- so the loop above never boxed it, and a spot selected with T had no box,
## no range and no LOCK on the glass.
func _draw_spot_target() -> void:
	var t: Node3D = aircraft.target
	if not is_instance_valid(t) or not t.is_in_group("laser_spots"):
		return
	var p: Vector3 = t.global_position
	if not _visible_pt(p):
		return
	var s := _project(p)
	if not _in_hud(s):
		return
	var d := aircraft.global_position.distance_to(p)
	var col := LASER if bool(t.get("lasing")) else AMBER
	var q := 16.0
	draw_polyline(PackedVector2Array([s + Vector2(0, -q), s + Vector2(q, 0),
		s + Vector2(0, q), s + Vector2(-q, 0), s + Vector2(0, -q)]), col, 2.0)
	_txt(s + Vector2(q + 8, -10), Sim.label_of(t), 12, col)
	_txt(s + Vector2(q + 8, 6), "%.1fkm" % (d * 0.001), 13, col)
	if aircraft.locked:
		var stop := aircraft.shot_blocked(aircraft.current_weapon(), t)
		draw_arc(s, q + 8.0, 0, TAU, 24, col, 1.4)
		_txt(s + Vector2(q + 8, 22), "LOCK" if stop == "" else stop, 13,
			col if stop == "" else RED)
	else:
		draw_arc(s, q + 8.0, _t * 3.0, _t * 3.0 + PI, 12, col, 1.2)

## Where the sensor is looking, marked on the main view.
##
## The pod's picture is a page of its own -- a corner of the screen, or all of
## it -- and nothing on the view you fly by said where it was pointed. A track
## held off the nose had no mark at all: you could designate a column, close
## the page, and have no idea which way to turn to attack it. A square with a
## cross on it while a track is held, a ring while the head is only slewing,
## and an arrow at the edge of the screen when the point is off it.
func _draw_sensor_mark() -> void:
	if pod == null or not is_instance_valid(pod) or pod.platform != aircraft:
		return
	var holding: bool = pod.mode != SensorPod.SLEW
	if not holding and not pod.active:
		return
	var p: Vector3 = pod.aim_point()
	if p == Vector3.INF:
		return
	var col := Color(0.55, 1.0, 0.72)
	var d := aircraft.global_position.distance_to(p)
	var rect := get_viewport_rect().grow(-24.0)
	var on_screen := _visible_pt(p) and rect.has_point(_project(p))
	if on_screen:
		var s := _project(p)
		if holding:
			var q := 11.0
			_box(Rect2(s - Vector2(q, q), Vector2(q, q) * 2.0), col, 1.6)
			draw_line(s - Vector2(q + 6, 0), s - Vector2(4, 0), col, 1.2)
			draw_line(s + Vector2(4, 0), s + Vector2(q + 6, 0), col, 1.2)
			draw_line(s - Vector2(0, q + 6), s - Vector2(0, 4), col, 1.2)
			draw_line(s + Vector2(0, 4), s + Vector2(0, q + 6), col, 1.2)
		else:
			draw_arc(s, 9.0, 0.0, TAU, 16, col, 1.4)
		var tag: String = ["SLEW", "AREA", "TRACK"][pod.mode]
		_txt(s + Vector2(16, 22), "TGP %s  %.1fkm" % [tag, d * 0.001], 12, col)
		return
	# Off the screen, or behind: an arrow on the edge, toward it.
	var c := get_viewport_rect().size * 0.5
	var local: Vector3 = cam.global_transform.affine_inverse() * p
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var reach: float = minf(c.x, c.y) - 40.0
	var tip := c + dir * reach
	draw_line(tip, tip - dir.rotated(0.5) * 14.0, col, 2.0)
	draw_line(tip, tip - dir.rotated(-0.5) * 14.0, col, 2.0)
	_txt(tip - dir * 30.0 + Vector2(-26, 4), "TGP %.1fkm" % (d * 0.001), 12, col)

## True if nothing in the height field stands between the two points. Marched
## rather than raycast: the terrain has no collision mesh at all, it is an
## analytic field, so this is the only thing there is to ask.
func _los_clear(from: Vector3, to: Vector3) -> bool:
	return Sim.line_of_sight(from, to)

## A rectangle drawn as a dashed outline.
func _box_dashed(r: Rect2, col: Color, w := 1.0) -> void:
	var pts := [r.position, r.position + Vector2(r.size.x, 0),
		r.position + r.size, r.position + Vector2(0, r.size.y)]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		var seg := a.distance_to(b)
		var n := maxi(int(seg / 7.0), 2)
		for k in range(0, n, 2):
			var t0 := float(k) / float(n)
			var t1 := minf(float(k + 1) / float(n), 1.0)
			draw_line(a.lerp(b, t0), a.lerp(b, t1), col, w)

func _kt(n: Node) -> float:
	if "linear_velocity" in n:
		return n.linear_velocity.length() * 1.94384
	return 0.0

# ---------------------------------------------------------------- side panels
func _draw_left(vp: Vector2) -> void:
	var x := 90.0
	var y := vp.y * 0.5
	var kias := aircraft.ias * 1.94384
	_box(Rect2(x - 4, y - 15, 92, 30), GREEN, 1.4)
	_txt(Vector2(x + 84, y + 7), "%d" % int(kias), 20, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 84)
	_txt(Vector2(x - 4, y - 24), "KIAS", 12, DIM)
	# ...and what it is actually doing over the ground. The two are the same on
	# the deck and nothing like each other high up: the air at ten kilometres is
	# a third as dense, so the box reads a little over half the real speed, and
	# the map then goes past at a rate the needle never claimed.
	_txt(Vector2(x - 4, y - 40), "GS %d" % int(aircraft.linear_velocity.length() * 1.94384),
		13, DIM)
	_txt(Vector2(x - 4, y + 34), "M %.2f" % aircraft.mach, 15, GREEN)
	_txt(Vector2(x - 4, y + 54), "G %+.1f" % aircraft.g_load, 15,
		RED if absf(aircraft.g_load) > aircraft.spec["g_limit"] else GREEN)
	# the peak sits alongside so you can see what the pull actually cost
	_txt(Vector2(x - 4, y + 70), "MAX %+.1f  MIN %+.1f" % [aircraft.g_peak, aircraft.g_min], 12,
		AMBER if aircraft.g_peak > aircraft.spec["g_limit"] else GREEN)
	if aircraft.g_strain > 0.05:
		_txt(Vector2(x - 4, y + 86), "GREY-OUT", 13, RED if aircraft.g_strain > 0.5 else AMBER)
	elif aircraft.g_red > 0.05:
		_txt(Vector2(x - 4, y + 86), "RED-OUT", 13, RED if aircraft.g_red > 0.5 else AMBER)
	_txt(Vector2(x - 4, y + 74), "AOA %.1f" % rad_to_deg(aircraft.aoa), 15,
		AMBER if aircraft.stalling else GREEN)
	# speed tape
	var tape_x := x + 96.0
	for i in range(-5, 6):
		var v := snappedf(kias, 25.0) + i * 25.0
		if v < 0:
			continue
		var ty := y - (v - kias) * 2.4
		if absf(ty - y) > 130:
			continue
		draw_line(Vector2(tape_x, ty), Vector2(tape_x + (10 if int(v) % 50 == 0 else 5), ty), DIM, 1.2)
		if int(v) % 50 == 0:
			_txt(Vector2(tape_x + 14, ty + 5), "%d" % int(v), 12, DIM)

func _draw_right(vp: Vector2) -> void:
	var x := vp.x - 150.0
	var y := vp.y * 0.5
	var alt := aircraft.global_position.y * 3.28084
	_box(Rect2(x, y - 15, 104, 30), GREEN, 1.4)
	_txt(Vector2(x + 98, y + 7), "%d" % int(alt), 20, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 96)
	_txt(Vector2(x, y - 24), "ALT FT MSL", 12, DIM)
	var agl := aircraft.agl * 3.28084
	_txt(Vector2(x, y + 34), "R %d" % int(agl), 15, AMBER if agl < 500.0 else GREEN)
	_txt(Vector2(x, y + 54), "VS %+d" % int(aircraft.vspeed * 196.85), 15,
		RED if aircraft.vspeed * 196.85 < -2200.0 else GREEN)
	# vertical speed bar
	var bx := x - 26.0
	draw_line(Vector2(bx, y - 110), Vector2(bx, y + 110), DIM, 1.2)
	var vsn := clampf(aircraft.vspeed / 60.0, -1.0, 1.0)
	draw_line(Vector2(bx - 7, y - vsn * 110.0), Vector2(bx + 7, y - vsn * 110.0), GREEN, 2.4)

func _draw_heading(vp: Vector2) -> void:
	var b := aircraft.global_transform.basis
	var fwd := -b.z
	var hdg := fmod(rad_to_deg(atan2(fwd.x, -fwd.z)) + 360.0, 360.0)
	var cx := vp.x * 0.5
	var top := 46.0
	_box(Rect2(cx - 34, top - 26, 68, 24), GREEN, 1.4)
	_txt(Vector2(cx + 30, top - 8), "%03d" % int(round(hdg)), 17, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 60)
	for i in range(-9, 10):
		var deg := snappedf(hdg, 5.0) + i * 5.0
		var dx := (deg - hdg) * 9.0
		if absf(dx) > 250.0:
			continue
		var d := fmod(deg + 720.0, 360.0)
		var big := int(round(d)) % 10 == 0
		draw_line(Vector2(cx + dx, top + 2), Vector2(cx + dx, top + (12 if big else 6)), DIM, 1.2)
		if int(round(d)) % 30 == 0:
			var lbl: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(int(round(d)),
				"%02d" % int(round(d) / 10.0))
			_txt(Vector2(cx + dx - 22.0, top + 30), lbl, 13, GREEN, HORIZONTAL_ALIGNMENT_CENTER, 44.0)
	draw_line(Vector2(cx, top - 2), Vector2(cx - 6, top - 10), GREEN, 1.6)
	draw_line(Vector2(cx, top - 2), Vector2(cx + 6, top - 10), GREEN, 1.6)

# ---------------------------------------------------------------- status
func _draw_status(vp: Vector2) -> void:
	var y := vp.y - 168.0
	var x := 40.0
	# throttle / afterburner
	var h := 96.0
	_box(Rect2(x, y, 16, h), DIM, 1.2)
	var t := aircraft.throttle
	draw_rect(Rect2(x + 2, y + h - 2 - (h - 4) * t, 12, (h - 4) * t),
		AMBER if t > 0.78 else GREEN)
	draw_line(Vector2(x - 4, y + h * (1.0 - 0.78)), Vector2(x + 20, y + h * (1.0 - 0.78)), AMBER, 1.0)
	_txt(Vector2(x - 6, y + h + 16), "THR", 13, DIM)
	_txt(Vector2(x - 6, y + h + 32), "%d%%" % int(t * 100.0), 14, GREEN)
	# An aeroplane with no reheat has no "AB" band: past the military stop it is
	# simply at maximum, and labelling it otherwise on an A-10 or a Hercules is
	# telling the pilot about a gate that is not there.
	var reheat: bool = aircraft != null and float(aircraft.spec.get("thrust_ab", 0.0)) \
		> float(aircraft.spec.get("thrust_mil", 1.0)) * 1.04
	var hot: bool = t > 0.78
	var word := ("AB" if reheat else "MAX") if hot else "MIL"
	_txt(Vector2(x - 2, y - 6), word, 13, AMBER if (hot and reheat) else DIM)
	# fuel
	var fx := x + 52.0
	var fr: float = aircraft.fuel / maxf(aircraft.spec["fuel"], 1.0)
	_box(Rect2(fx, y, 16, h), DIM, 1.2)
	draw_rect(Rect2(fx + 2, y + h - 2 - (h - 4) * fr, 12, (h - 4) * fr),
		RED if fr < 0.12 else GREEN)
	_txt(Vector2(fx - 6, y + h + 16), "FUEL", 13, DIM)
	_txt(Vector2(fx - 6, y + h + 32), "%d" % int(aircraft.fuel), 14, RED if fr < 0.12 else GREEN)

	# gear / flaps / brakes
	var sx := vp.x * 0.5 - 130.0
	var sy := vp.y - 116.0
	var items := [
		["GEAR", aircraft.gear_anim > 0.99, aircraft.gear_anim > 0.01 and aircraft.gear_anim < 0.99],
		["FLAP", aircraft.flap_anim > 0.5, false],
		["BRK", aircraft.wheel_brake or aircraft.airbrake, false],
		["FBW", aircraft.assist, false],
	]
	for it in items:
		var col: Color = GREEN if it[1] else DIM
		if it[2]:
			col = AMBER if fmod(_t, 0.5) < 0.25 else DIM
		_txt(Vector2(sx, sy), it[0], 15, col)
		sx += 66.0

	# ---- weapon selector strip -------------------------------------------
	var strip_y := vp.y - 96.0
	var cell_w := 168.0
	var total := cell_w * float(aircraft.weapon_types.size())
	var sxx := vp.x * 0.5 - total * 0.5
	for i in aircraft.weapon_types.size():
		var w: String = aircraft.weapon_types[i]
		var sel: bool = i == aircraft.selected
		var label: String = aircraft.weapon_label(w)
		var count: int = aircraft.weapon_count(w)
		var empty: bool = count == 0
		var col := AMBER if sel else (Color(0.45, 0.5, 0.55) if empty else DIM)
		var r := Rect2(sxx + 4.0, strip_y, cell_w - 8.0, 46.0)
		if sel:
			draw_rect(r, Color(AMBER.r, AMBER.g, AMBER.b, 0.14), true)
		_box(r, col, 2.0 if sel else 1.0)
		_txt(Vector2(r.position.x + 8, r.position.y + 20), "%d" % (i + 1), 17, col)
		_txt(Vector2(r.position.x + 30, r.position.y + 20), label, 16, col)
		var qty: String = "belt" if count < 0 else (("%d rds" % count) if w == "gun" else ("x%d" % count))
		_txt(Vector2(r.position.x + 30, r.position.y + 39), qty, 14, col)
		sxx += cell_w
	# bay state sits right next to the stores it holds
	var has_bays: bool = aircraft.bays.values().any(func(b): return b["kind"] == "internal")
	var bx2 := vp.x * 0.5 - total * 0.5 - 178.0
	if has_bays:
		var bay_open := aircraft.any_bay_open()
		var bcol := AMBER if bay_open else DIM
		_box(Rect2(bx2, strip_y, 168.0, 46.0), bcol, 2.0 if bay_open else 1.0)
		_txt(Vector2(bx2 + 8, strip_y + 20), "B", 17, bcol)
		_txt(Vector2(bx2 + 28, strip_y + 20), "BAY " + ("OPEN" if bay_open else "SHUT"), 16, bcol)
		_draw_bay_icon(Vector2(bx2 + 118, strip_y + 34), bcol)
		if not bay_open and aircraft.current_weapon() != "gun":
			_txt(Vector2(bx2 + 28, strip_y + 39), "open to fire", 13, RED)
	else:
		_box(Rect2(bx2, strip_y, 168.0, 46.0), DIM, 1.0)
		_txt(Vector2(bx2 + 10, strip_y + 20), "EXTERNAL PYLONS", 14, DIM)
		_txt(Vector2(bx2 + 10, strip_y + 39), "always ready", 13, DIM)
	# stores rack + flares to the right of the strip
	var rx := vp.x * 0.5 + total * 0.5 + 16.0
	_txt(Vector2(rx, strip_y + 16), "STORES", 13, DIM)
	var px := rx
	for st in aircraft.stores:
		var col2 := DIM if st["gone"] else GREEN
		draw_rect(Rect2(px, strip_y + 24, 9, 18), col2, not st["gone"])
		if st["gone"]:
			_box(Rect2(px, strip_y + 24, 9, 18), col2, 1.0)
		px += 13.0
	# Named from the binding, not written out here: these said N and B long
	# after the flares moved to C and the chaff to V.
	_txt(Vector2(rx, strip_y + 58), "%s  FLARE %d" % [
		Sim.key_label(&"flare"), aircraft.flares], 14,
		GREEN if aircraft.flares > 24 else AMBER)
	_txt(Vector2(rx, strip_y + 76), "%s  CHAFF %d" % [
		Sim.key_label(&"chaff"), aircraft.chaff], 14,
		GREEN if aircraft.chaff > 24 else AMBER)

func _draw_bay_icon(at: Vector2, col: Color) -> void:
	var open := 0.0
	for k in aircraft.bays:
		open = maxf(open, aircraft.bays[k]["anim"] if aircraft.bays[k]["kind"] == "internal" else 0.0)
	draw_line(at + Vector2(-16, -6), at + Vector2(16, -6), col, 1.4)
	var a := deg_to_rad(60.0) * open
	for s in [-1.0, 1.0]:
		var hinge := at + Vector2(s * 16.0, -6)
		var tip := hinge + Vector2(-s * 16.0 * cos(a), 16.0 * sin(a))
		draw_line(hinge, tip, col, 2.0)

## Arma style corner panels: each side cycles off / sensor / radar / minimap
## with the bracket keys, so you choose what sits in your peripheral vision.
func _draw_panels(vp: Vector2) -> void:
	var slots := [
		[Sim.panel_left, Vector2(200.0, vp.y - 150.0)],
		[Sim.panel_right, Vector2(vp.x - 200.0, vp.y - 150.0)],
	]
	for slot in slots:
		match int(slot[0]):
			2:
				var _p := Sim.prof_at()
				_draw_radar_at(slot[1], 78.0)
				Sim.prof_end(&"hud.radar", _p)
			3:
				var _p2 := Sim.prof_at()
				_draw_minimap_at(slot[1], 82.0)
				Sim.prof_end(&"hud.minimap", _p2)
			1:
				_draw_sensor_stub(slot[1], 82.0)

## Compass rose minimap: contacts and the runway, oriented to your nose.
func _draw_minimap_at(c: Vector2, r: float) -> void:
	var rng: float = Sim.radar_range() * 0.35
	draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Color(0.02, 0.05, 0.04, 0.5), true)
	_box(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), DIM, 1.2)
	var b := aircraft.global_transform.basis
	var hdg := atan2(-b.z.x, b.z.z)
	var here := Vector2(aircraft.global_position.x, aircraft.global_position.z)
	# Heading up: screen right is the starboard vector, screen up is ahead.
	# With forward at (sin h, -cos h) and starboard at (cos h, sin h) that is a
	# rotation by *minus* the heading. Both sine terms were the other way round,
	# which rotates by plus the heading instead — so the picture came out turned
	# by twice the heading and only agreed with the world pointing due north.
	var to_screen := func(w: Vector2) -> Vector2:
		var d := (w - here) / rng * r
		return c + Vector2(d.x * cos(hdg) + d.y * sin(hdg),
			-d.x * sin(hdg) + d.y * cos(hdg))
	# runway
	var rw_a: Vector2 = to_screen.call(Vector2(0, -Sim.RUNWAY_LEN * 0.5))
	var rw_b: Vector2 = to_screen.call(Vector2(0, Sim.RUNWAY_LEN * 0.5))
	draw_line(rw_a, rw_b, Color(0.8, 0.85, 0.9, 0.8), 2.0)
	for z in _seen_zones:
		if not is_instance_valid(z):
			continue
		var col := Color(0.35, 0.75, 1.0) if z.owner_team == 0 else (
			RED if z.owner_team == 1 else Color(0.8, 0.8, 0.8))
		var zp: Vector2 = to_screen.call(Vector2(z.global_position.x, z.global_position.z))
		draw_circle(zp, 3.0, col)
	for k in _seen.size():
		var seen_k: Variant = _seen[k]
		if not is_instance_valid(seen_k):
			continue
		var n: Node3D = seen_k
		if not is_instance_valid(n) or n == aircraft:
			continue
		if _seen_what[k] & SEEN_MORTAL != 0 and not n.is_alive():
			continue
		var p: Vector2 = to_screen.call(Vector2(n.global_position.x, n.global_position.z))
		if (p - c).length() > r:
			continue
		var hostile: bool = ("team" in n) and n.team != aircraft.team
		draw_circle(p, 2.5, RED if hostile else Color(0.4, 0.85, 1.0))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(-5, 5),
		c + Vector2(5, 5)]), GREEN)
	_txt(c + Vector2(-r + 4, r - 6), "MAP %d km" % int(rng * 0.001), 12, DIM)

## Placeholder frame when the sensor is assigned to a side slot but stowed.
func _draw_sensor_stub(c: Vector2, r: float) -> void:
	draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Color(0.02, 0.05, 0.04, 0.5), true)
	_box(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), DIM, 1.2)
	_txt(c - Vector2(r - 8, -4), "SENSOR   ALT+RMB", 13, DIM)

## When each contact was last actually seen, so a masked one leaves a fading
## trace rather than vanishing the instant it goes behind something.
var _held := {}

## Whose radar this is. The scope was written against the aeroplane and read
## `jet` for everything, so a ship — which has a mast full of antennas and every
## reason to want one — had no scope at all.
var _scope_src: Node3D = null

func _scope_origin() -> Vector3:
	return _scope_src.global_position if is_instance_valid(_scope_src) \
		else (aircraft.global_position if is_instance_valid(aircraft) else Vector3.ZERO)

func _scope_basis() -> Basis:
	return _scope_src.global_transform.basis if is_instance_valid(_scope_src) \
		else (aircraft.global_transform.basis if is_instance_valid(aircraft) else Basis())

func _scope_team() -> int:
	if is_instance_valid(_scope_src) and "team" in _scope_src:
		return int(_scope_src.team)
	return int(aircraft.team) if is_instance_valid(aircraft) else 0

## How far the scope reaches: the mount's own radar if it has one, otherwise
## the selected range on the aeroplane's set.
func _scope_reach() -> float:
	if is_instance_valid(_scope_src) and _scope_src.has_method("radar_range"):
		var rr: float = float(_scope_src.call("radar_range"))
		if rr > 0.0:
			return rr
	return Sim.radar_range()

func _scope_target() -> Node:
	if is_instance_valid(_scope_src):
		return _scope_src.ai_target if "ai_target" in _scope_src else null
	return aircraft.target if is_instance_valid(aircraft) else null

func _draw_radar_at(c: Vector2, r: float) -> void:
	for k in _held.keys():
		if not is_instance_valid(k) or _t - float(_held[k]) > 10.0:
			_held.erase(k)
	draw_arc(c, r, 0, TAU, 40, DIM, 1.2)
	draw_arc(c, r * 0.5, 0, TAU, 30, Color(DIM.r, DIM.g, DIM.b, 0.25), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(DIM.r, DIM.g, DIM.b, 0.25), 1.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(DIM.r, DIM.g, DIM.b, 0.25), 1.0)
	# Scale to whatever set is actually doing the looking. A battery's search
	# radar reaches seventy-eight kilometres and the scope was drawing it at the
	# aeroplane's selected range whatever it was mounted on.
	var reach: float = _scope_reach()
	_txt(c + Vector2(-r, r + 16), "RADAR  %d km   [ ] panels   - = range" % int(reach * 0.001), 12, DIM)
	var b := _scope_basis()
	var origin := _scope_origin()
	var my_team := _scope_team()
	var my_target := _scope_target()
	var fwd := -b.z
	var hdg := atan2(fwd.x, -fwd.z)
	for k in _seen.size():
		var seen_k: Variant = _seen[k]
		if not is_instance_valid(seen_k):
			continue
		var n: Node3D = seen_k
		if not is_instance_valid(n) or n == _scope_src or n == aircraft:
			continue
		if _seen_what[k] & SEEN_NO_LOCK != 0:
			continue
		if _seen_what[k] & SEEN_MORTAL != 0 and not n.is_alive():
			continue
		var rel: Vector3 = n.global_position - origin
		var d := rel.length()
		if d > reach:
			continue
		var bearing := atan2(rel.x, -rel.z) - hdg
		var rr := r * clampf(d / reach, 0.0, 1.0)
		var p := c + Vector2(sin(bearing), -cos(bearing)) * rr
		var hostile: bool = ("team" in n) and int(n.team) != my_team
		var col := RED if hostile else Color(0.4, 0.8, 1.0)
		# Terrain masking, on the scope as well as on the lock. A contact behind
		# a ridge is not a return; painting it solid and then refusing to lock
		# it is worse than not painting it, because the pilot can see it and
		# cannot understand why the radar will not take it.
		# Settled at ten hertz with the rest of the list -- see `_refresh_masking`.
		var masked: bool = d > 2000.0 and k < _seen_clear.size() \
			and _seen_clear[k] == 0
		if masked:
			# a faded memory trace where it was last seen, and nothing more
			if _held.has(n) and _t - float(_held[n]) < 8.0:
				var fade: float = clampf(1.0 - (_t - float(_held[n])) / 8.0, 0.0, 1.0)
				draw_arc(p, 3.0, 0, TAU, 8,
					Color(col.r, col.g, col.b, 0.30 * fade), 1.0)
			continue
		_held[n] = _t
		if n is GroundTarget:
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), col, false, 1.4)
		else:
			draw_circle(p, 3.5, col)
		if n == my_target:
			draw_arc(p, 7.0, 0, TAU, 12, AMBER, 1.4)
	# Our own laser spot, as a diamond: a mark rather than a return, but a thing
	# you can put the radar on and send a laser-guided round at, so it is drawn
	# where you can see it and pick it.
	for sp in get_tree().get_nodes_in_group("laser_spots"):
		if not is_instance_valid(sp) or not bool(sp.get("on")) \
				or int(sp.get("team")) != my_team:
			continue
		var rel3: Vector3 = (sp as Node3D).global_position - origin
		if rel3.length() > reach:
			continue
		var bearing3 := atan2(rel3.x, -rel3.z) - hdg
		var p3 := c + Vector2(sin(bearing3), -cos(bearing3)) \
			* (r * clampf(rel3.length() / reach, 0.0, 1.0))
		var lc := LASER if bool(sp.get("lasing")) else AMBER
		var dq := 4.5
		draw_polyline(PackedVector2Array([p3 + Vector2(0, -dq), p3 + Vector2(dq, 0),
			p3 + Vector2(0, dq), p3 + Vector2(-dq, 0), p3 + Vector2(0, -dq)]), lc, 1.6)
		if sp == my_target:
			draw_arc(p3, 8.0, 0, TAU, 12, AMBER, 1.4)
	# Rounds in the air. Yours flash blue, anything tracking you flashes red.
	#
	# The old test was `m.target != _scope_src and m.target != jet`, and in an
	# aeroplane `_scope_src` is null — so any round with no target at all
	# compared null to null, failed the test and was painted as an inbound
	# threat. Your own bombs, and any missile that had lost its lock, blinked
	# red on the scope as though they were coming for you.
	var me: Node = _scope_src if is_instance_valid(_scope_src) else aircraft
	var blink := fmod(_t, 0.3) < 0.15
	if blink:
		for m in get_tree().get_nodes_in_group("missiles"):
			if not is_instance_valid(m):
				continue
			var mine: bool = is_instance_valid(m.shooter) and m.shooter == me
			var friendly: bool = (not mine) and ("team" in m) and int(m.team) == my_team
			var at_me: bool = is_instance_valid(m.target) and m.target == me
			if not (mine or friendly or at_me):
				continue
			var rel2: Vector3 = m.global_position - origin
			if rel2.length() > Sim.radar_range():
				continue
			var bearing2 := atan2(rel2.x, -rel2.z) - hdg
			var p2 := c + Vector2(sin(bearing2), -cos(bearing2)) \
				* (r * clampf(rel2.length() / Sim.radar_range(), 0, 1))
			if at_me and not mine:
				draw_circle(p2, 5.0, RED)
			elif mine:
				draw_circle(p2, 4.5, Color(0.35, 0.72, 1.0))
			else:
				# somebody else on your side has one in the air
				draw_circle(p2, 3.0, Color(0.30, 0.60, 0.95, 0.75))

# ------------------------------------------------------------- ground service
## Rearming on the ground, said on the glass. The crew came out and went to
## work with nothing on the screen but a line in the message log, and when the
## aeroplane was rolling, or parked just outside the area they cover, nothing
## at all -- so "there is nowhere to rearm" was a reasonable thing to conclude.
func _draw_service(vp: Vector2) -> void:
	if aircraft == null or not aircraft.on_ground or not aircraft.near_service():
		return
	if not aircraft.needs_service() and not aircraft.servicing:
		return
	var y: float = vp.y * 0.5 + 170.0
	if aircraft.servicing:
		var fuel_pct: float = 100.0 * aircraft.fuel / maxf(float(aircraft.spec["fuel"]), 1.0)
		var have := 0
		for st in aircraft.stores:
			if not st["gone"]:
				have += 1
		_txt(Vector2(0, y), "GROUND CREW — FUEL %d%%   STORES %d/%d   ROUNDS %d" % [
			int(fuel_pct), have, aircraft.stores.size(), aircraft.ammo], 16, GREEN,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	elif aircraft.linear_velocity.length() > 1.5:
		_txt(Vector2(0, y), "STOP TO REARM AND REFUEL", 16, AMBER,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x)

# ---------------------------------------------------------------- landing aid
func _draw_landing(vp: Vector2) -> void:
	if base == null:
		return
	var p := aircraft.global_position
	var aim := Vector3(0, 0, Airbase.AIM_Z)
	var to_36 := p.z > Airbase.AIM_Z
	var d := Vector2(p.x - aim.x, p.z - aim.z).length()
	if not (aircraft.gear_down and d < 18000.0 and aircraft.agl < 3000.0):
		return
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var gs_ang := rad_to_deg(atan2(maxf(p.y, 0.0), maxf(d, 1.0)))
	var dev_gs := clampf((gs_ang - Airbase.GLIDE) / 1.6, -1.0, 1.0)
	var loc := p.x if to_36 else -p.x
	var dev_loc := clampf(loc / maxf(d * 0.06, 40.0), -1.0, 1.0)
	var half := 130.0
	draw_line(Vector2(cx - half, cy - half * dev_gs), Vector2(cx + half, cy - half * dev_gs), Color(0.4, 0.85, 1.0, 0.9), 2.0)
	draw_line(Vector2(cx + half * dev_loc, cy - half), Vector2(cx + half * dev_loc, cy + half), Color(0.4, 0.85, 1.0, 0.9), 2.0)
	for i in [-1.0, -0.5, 0.5, 1.0]:
		draw_arc(Vector2(cx + half * i, cy), 3.0, 0, TAU, 8, Color(0.4, 0.85, 1.0, 0.5), 1.0)
		draw_arc(Vector2(cx, cy + half * i), 3.0, 0, TAU, 8, Color(0.4, 0.85, 1.0, 0.5), 1.0)
	var txt := "RWY %s   %.1f km   GS %.1f deg" % ["36" if to_36 else "18", d * 0.001, gs_ang]
	_txt(Vector2(cx - 150, cy + half + 26), txt, 14, Color(0.5, 0.9, 1.0))
	if aircraft.on_ground and Sim.on_runway(p.x, p.z):
		var heading_north: bool = (-aircraft.global_transform.basis.z).z < 0.0
		var rem: float = (p.z + Sim.RUNWAY_LEN * 0.5) if heading_north else (Sim.RUNWAY_LEN * 0.5 - p.z)
		_txt(Vector2(cx - 60, cy + half + 46), "REMAINING %d m" % int(rem), 15,
			RED if rem < 400.0 else GREEN)

# ---------------------------------------------------------------- warnings
func _draw_warnings(vp: Vector2, c: Vector2) -> void:
	var blink := fmod(_t, 0.6) < 0.35
	var y := c.y - 150.0
	if not aircraft.alive:
		_txt(Vector2(0, c.y - 40), "AIRCRAFT DESTROYED", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		_txt(Vector2(0, c.y + 6), "ESC for the menu", 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		return
	if (aircraft.missile_warn > 0.0 or aircraft.missile_tti < INF) and blink:
		_txt(Vector2(0, y), "MISSILE  —  BREAK AND FLARE", 26, RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 34.0
	if aircraft.stalling and blink:
		_txt(Vector2(0, y), "STALL", 24, AMBER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 30.0
	if aircraft.agl < 150.0 and aircraft.vspeed < -12.0 and not aircraft.gear_down and blink:
		_txt(Vector2(0, y), "PULL UP", 26, RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 30.0
	if aircraft.fuel < aircraft.spec["fuel"] * 0.1 and blink:
		_txt(Vector2(0, y), "BINGO FUEL", 20, AMBER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 26.0
	if aircraft.health < 55.0:
		_txt(Vector2(0, y), "DAMAGE %d%%" % int(100.0 - aircraft.health), 20,
			RED if aircraft.health < 30.0 else AMBER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	if ("msg_t" in aircraft) and aircraft.msg_t > 0.0:
		_txt(Vector2(0, vp.y - 176.0), String(aircraft.msg).to_upper(), 19, WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x)

func _draw_log(vp: Vector2) -> void:
	# A column on the right that fits the screen, each message wrapped to it.
	# The lines were drawn from a fixed 300 px in and never measured, so any
	# message longer than that ran straight off the edge of the screen.
	const PT := 14
	var w: float = clampf(vp.x * 0.30, 220.0, 440.0)
	var x: float = vp.x - w - 16.0
	var y := 90.0
	for l in log_lines:
		var a: float = clampf(1.0 - (l["age"] - 5.0) / 2.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var col: Color = [WHITE, GREEN, RED][int(l["k"])]
		col.a = a
		# Broken into lines once, when it is first drawn at this width, and
		# kept on the message. It was measured word by word every frame for
		# as long as it was on screen -- a dozen shaped strings a message.
		if float(l.get("wrap_w", -1.0)) != w:
			l["wrap"] = _wrap(str(l["t"]), w, PT)
			l["wrap_w"] = w
		for part in (l["wrap"] as PackedStringArray):
			_txt(Vector2(x, y), part, PT, col, HORIZONTAL_ALIGNMENT_RIGHT, w)
			y += 18.0
		y += 2.0

## Break a line of text at spaces so that no piece is wider than `w`.
func _wrap(t: String, w: float, pt: int) -> PackedStringArray:
	var out := PackedStringArray()
	if _font == null or _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, pt).x <= w:
		out.append(t)
		return out
	var line := ""
	for word in t.split(" "):
		var trial: String = word if line == "" else line + " " + word
		if line != "" and _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, pt).x > w:
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out

## Above this many sectors the banner stops naming them one by one.
const COMPACT_SECTORS := 8

func _sector_colour(z: Dictionary) -> Color:
	if bool(z["locked"]):
		return Color(0.4, 0.4, 0.42)
	if bool(z["contested"]):
		return AMBER
	if int(z["team"]) == 0:
		return Color(0.35, 0.75, 1.0)
	if int(z["team"]) == 1:
		return RED
	return Color(0.75, 0.75, 0.78)

## Tickets, sector strip and the mode banner.
## The match as the banner draws it, asked for with the contact list rather
## than every frame: it is a dictionary built per sector, eighteen of them in
## a conquest, for numbers that change a few times a second.
var _mode_state: Dictionary = {}

func _draw_mode(vp: Vector2) -> void:
	if _mode_state.is_empty():
		_mode_state = mode.hud_state()
	var st: Dictionary = _mode_state
	var cx := vp.x * 0.5
	var y := 96.0
	var name_map := {"conquest": "CONQUEST", "rush": "RUSH", "warlords": "WARLORDS",
		"tdm": "TEAM DEATHMATCH", "ffa": "FREE FOR ALL", "strike": "STRIKE",
		"cqb": "CLOSE QUARTERS", "ground": "GROUND COMBAT", "arms": "COMBAT"}
	_txt(Vector2(0, y), str(name_map.get(st["mode"], st["mode"])).to_upper(), 15,
		Color(0.7, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	y += 22.0
	if st["mode"] == "strike":
		_txt(Vector2(0, y), "WAVE %d    %d LEFT    %d DESTROYED" % [int(st["wave"]),
			int(st["left"]), int(st["destroyed"])], 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 26.0
	elif st["mode"] in ["tdm", "ffa", "cqb", "ground", "arms"]:
		var k: Dictionary = st["kills"]
		_txt(Vector2(0, y), "US %d    —    THEM %d    (to %d)" % [int(k.get(0, 0)),
			int(k.get(1, 0)), int(st["goal"])], 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 26.0
	else:
		var t: Dictionary = st["tickets"]
		var bw := 150.0
		for side in [0, 1]:
			var frac: float = clampf(float(t.get(side, 0)) / 400.0, 0.0, 1.0)
			var bx: float = cx - bw - 14.0 if side == 0 else cx + 14.0
			var col := Color(0.35, 0.75, 1.0) if side == 0 else RED
			_box(Rect2(bx, y - 12, bw, 16), col, 1.2)
			var fill := bw * frac
			draw_rect(Rect2(bx if side == 0 else bx + bw - fill, y - 11, fill, 14), col)
			_txt(Vector2(bx, y + 26), "%d" % int(t.get(side, 0)), 14, col,
				HORIZONTAL_ALIGNMENT_CENTER, bw)
		y += 30.0
	var zs: Array = st["zones"]
	if not zs.is_empty():
		# A labelled box per sector is 44 px wide, which was fine for the five
		# the map used to have and is eight hundred pixels of banner for the
		# eighteen it has now. Past a handful the sectors become a strip of
		# ticks -- still one mark each, still every state readable -- and the
		# thing you actually steer by becomes the income.
		if zs.size() <= COMPACT_SECTORS:
			var w := 44.0
			var sx := cx - w * float(zs.size()) * 0.5
			for z in zs:
				var col := _sector_colour(z)
				_box(Rect2(sx + 5, y, w - 10, 26), col, 1.4)
				var pr: float = (float(z["prog"]) + 1.0) * 0.5
				draw_rect(Rect2(sx + 6, y + 20, (w - 12) * pr, 4), col)
				_txt(Vector2(sx + 5, y + 19), str(z["label"]), 16, col,
					HORIZONTAL_ALIGNMENT_CENTER, w - 10)
				sx += w
			y += 40.0
		else:
			var tick := 9.0
			var sw: float = tick * float(zs.size())
			var sx2: float = cx - sw * 0.5
			for z2 in zs:
				var col2 := _sector_colour(z2)
				# a tick, filled by how far its capture has got
				draw_rect(Rect2(sx2 + 1.0, y + 2.0, tick - 2.0, 18.0),
					Color(col2.r, col2.g, col2.b, 0.22))
				var pr2: float = (float(z2["prog"]) + 1.0) * 0.5
				draw_rect(Rect2(sx2 + 1.0, y + 20.0 - 18.0 * pr2, tick - 2.0,
					18.0 * pr2), col2)
				sx2 += tick
			y += 26.0
			_txt(Vector2(0, y), "SECTORS %d / %d" % [int(st["held"]), zs.size()],
				13, Color(0.72, 0.82, 0.92), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			y += 19.0
			if str(st.get("objective", "")) != "":
				_txt(Vector2(0, y), "OBJECTIVE  %s" % str(st["objective"]), 14,
					AMBER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
				y += 20.0
	if int(st["cp"]) > 0:
		var rate: float = float(st.get("cp_rate", 0.0))
		var line := "COMMAND POINTS %d" % int(st["cp"])
		if rate > 0.0:
			line += "      +%d / min" % int(round(rate))
		else:
			line += "      no income"
		_txt(Vector2(0, y), line, 14,
			Color(0.7, 1.0, 0.8) if rate > 0.0 else Color(0.85, 0.7, 0.55),
			HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	if str(st["result"]) != "":
		_txt(Vector2(0, vp.y * 0.34), str(st["result"]), 30,
			GREEN if str(st["result"]).begins_with("VICTORY") else RED,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x)

func _ship_keys() -> Array:
	var conn := [
		["A / D", "wheel: port / starboard"],
		["W / S", "telegraph: ahead / astern"],
		["P", "view: conning tower / close / chase / wide"],
		["RMB (hold)", "zoom the view"],
		["N", "night vision"],
		["M", "tactical map"],
		["U", "hand over the conn"],
	]
	if ship.can_dive():
		conn.append(["F / R", "dive / surface"])
	var arms := [
		["1 - 2", "select weapon by number"],
		["\\", "cycle weapon"],
		["T", "cycle target"],
		["SPACE", "fire the selected weapon"],
		["O", "sensor page"],
		["I", "sensor channel"],
		["L", "laser"],
		["CTRL + T", "track what the sight is on"],
	]
	if ship.can_launch():
		arms.append(["RMB on the map", "lay the strategic aiming point"])
	if not ship.armed():
		# A merchant hull, or a boat with her tubes shot dry: the sensor is
		# still hers, the weapon keys are not.
		return [["THE CONN", conn], ["SENSOR", [
			["O", "sensor page"],
			["I", "sensor channel"],
			["CTRL + T", "track what the sight is on"],
		]], ["GENERAL", _general_keys()]]
	return [["THE CONN", conn], ["WEAPONS", arms], ["GENERAL", _general_keys()]]

## The carrier's bridge. She has nothing to fire, so the card says so by
## leaving it off: the aeroplane's card stood here before, offering a gun, a
## weapon select and a gunner station on a ship that carries none of them.
func _conn_keys() -> Array:
	return [["THE CONN", [
		["A / D", "wheel: port / starboard"],
		["W / S", "telegraph: ahead / astern"],
		["mouse", "look out from the island"],
		["RMB (hold)", "zoom the view"],
		["O / ALT+RMB", "sensor page"],
		["TAB", "sensor, all stop, amidships, hand over"],
		["M", "tactical map"],
		["U", "hand over the conn"],
	]], ["GENERAL", _general_keys()]]

func _rocket_keys() -> Array:
	return [["THE ROCKET", [
		["SHIFT / CTRL", "throttle up / down"],
		["X", "engine cut"],
		["W / S", "pitch"],
		["Q / E", "yaw"],
		["A / D", "roll"],
		["T", "attitude: free, hold, prograde, retrograde"],
		["H", "autopilot: to orbit; in the moon rocket, on to the moon"],
		["SPACE", "drop the spent stage, light the next"],
		[", / .", "time warp, coasting above the air"],
		["mouse / wheel", "look round / closer and further"],
		["U", "climb out, once it is down"],
	]], ["TO ORBIT", [
		["1", "full throttle, straight up"],
		["2", "from a kilometre up, lean east a little at a time"],
		["3", "past 40 km, T to PROGRADE and let it follow"],
		["4", "cut when LOW POINT passes 150 km"],
	]], ["GENERAL", _general_keys()]]

func _tank_keys() -> Array:
	return [
		["DRIVING", [
			["W / S", "throttle ahead / astern"],
			["A / D", "steer"],
			["P", "view"],
			["N", "night vision"],
			["M", "tactical map"],
			["U", "dismount"],
		]],
		["THE GUN", [
			["mouse", "lay the turret"],
			["1 - 3", "select weapon"],
			["\\", "cycle weapon"],
			["SPACE", "fire"],
			["O", "commander\'s sight"],
			["RMB on the map", "lay a fire mission"],
		]],
		["GENERAL", _general_keys()],
	]

func _foot_keys() -> Array:
	return [
		["ON FOOT", [
			["WASD", "walk"],
			["SHIFT", "sprint  ( weapon down, spends wind )"],
			["C / CTRL", "crouch on and off  ( from a sprint: slide )"],
			["Z", "prone on and off"],
			["under canopy", "A D turn, W run on and sink, S brake and hold up"],
			["SPACE", "jump  /  vault  /  climb  —  at a tall wall: take hold of it"],
			["on a wall", "W S A D climb, SHIFT faster, SPACE kick off, C let go"],
			["F", "pick up a dropped weapon"],
			["4 - 7", "kill streaks, cheapest first — chosen on the deploy screen"],
			["", "airstrike and fire mission open the map: click the spot"],
			["M", "map — wheel zooms right in to the streets"],
			["Q / E", "lean left / right"],
			["LMB", "fire"],
			["RMB", "sights"],
			["1 - 3", "the two long guns and the sidearm"],
			["R", "reload"],
			["G", "grenade"],
			["X", "flashbang"],
			["P", "first person / over the shoulder"],
			["B", "binoculars"],
			["N", "night vision"],
			["U", "board what you are standing at"],
		]],
		["GENERAL", _general_keys()],
	]

func _general_keys() -> Array:
	return [
		["F2", "this card"],
		["F3", "admin"],
		["/", "chat"],
		["ESC", "menu"],
	]

func _air_keys() -> Array:
	var groups := [
		["FLYING", [
			["W / S", "pitch down / up"],
			["A / D", "roll left / right"],
			["Q / E", "rudder"],
			["SHIFT / CTRL", "throttle + afterburner"],
			[";", "mouse as stick"],
			["M", "tactical map"],
			["H", "fly-by-wire on / off"],
		]],
		["RUNWAY", [
			["G", "landing gear up / down"],
			["J", "gunner station (gunships)"],
			["F", "flaps"],
			["X", "wheel brakes / airbrake"],
		]],
		["WEAPONS", [
			["1 - 8", "select weapon by number"],
			["\\", "cycle weapon"],
			["B", "open + close weapon bay"],
			["T", "cycle target"],
			["LMB / SPACE", "fire selected weapon"],
			["K", "gun burst"],
			["L", "landing / flood lamp"],
			["C", "flares"],
			["V", "chaff"],
		]],
		["SENSORS", [
			["RMB (hold)", "zoom the view"],
			["O / ALT+RMB", "raise / stow the sensor page"],
			["CTRL+T", "designate  ( point track )"],
			["L", "laser"],
			["N", "sensor channel  TV / night / white hot / black hot"],
			["[  ]", "left / right side panels"],
			["=  -", "radar range"],
		]],
		["MOUSE STICK", [
			[";", "mouse stick on / off"],
			["MOUSE", "then fly it like a stick: forward is nose down"],
			["", "the further from centre, the more deflection"],
			["", "release to centre; the FBW holds what you ask for"],
			["ALT + mouse", "look around instead of flying"],
		]],
		["VIEW", [
			["P", "cockpit / chase / orbit"],
			["N", "night vision"],
			["ALT + mouse", "look around"],
			["Y", "weapon camera"],
			["M", "map"],
			["TAB", "aircraft actions"],
			["F3", "air traffic: call aircraft in to land"],
			["ESC", "menu   ( F2 hides this )"],
		]],
	]
	return groups

## The key card, on a canvas of its own.
##
## It is a page of static text -- eighty-odd strings laid out and measured --
## and it was drawn again on every frame of the game. Measured, 0.68 ms of a
## 14 ms frame for a picture that changes only when you climb into something
## else or press F2. A control of its own draws it once and is told to redraw
## only when the list it shows has actually changed.
class KeyCard extends Control:
	var font: Font
	var groups: Array = []

	func show_keys(g: Array) -> void:
		groups = g
		queue_redraw()

	func _draw() -> void:
		if font == null or groups.is_empty():
			return
		var x := 26.0
		var y := 118.0
		var panel_h := 0.0
		for g in groups:
			panel_h += 26.0 + float(g[1].size()) * 19.0
		var box := Rect2(x - 14, y - 30, 330, panel_h + 24)
		draw_rect(box, Color(0.02, 0.04, 0.06, 0.55), true)
		draw_rect(box, Color(0.4, 0.9, 0.6, 0.35), false, 1.0)
		for g in groups:
			draw_string(font, Vector2(x, y), str(g[0]),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.45, 0.95, 0.65))
			y += 22.0
			for row in g[1]:
				draw_string(font, Vector2(x + 6, y), str(row[0]),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 0.95, 0.7))
				draw_string(font, Vector2(x + 116, y), str(row[1]),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.82, 0.9, 0.95))
				y += 19.0
			y += 4.0

var _card: KeyCard = null
## What the card is currently showing, as one integer: which seat, and the two
## things a ship's list depends on. Compared every frame, which costs nothing;
## the list is only rebuilt and redrawn when it differs.
var _card_sig := -1

## Which keys apply where you are sitting, and whether that has changed.
func _refresh_help() -> void:
	if _card == null:
		return
	var sig := 0
	if show_help:
		if rocket != null and is_instance_valid(rocket):
			sig = 256
		elif carrier != null and is_instance_valid(carrier):
			sig = 64
		elif ship != null and is_instance_valid(ship):
			sig = 1 | (2 if ship.can_dive() else 0) | (4 if ship.can_launch() else 0) \
				| (128 if ship.armed() else 0)
		elif tank != null and is_instance_valid(tank):
			sig = 8
		elif walker != null and is_instance_valid(walker):
			sig = 16
		else:
			sig = 32
	if sig == _card_sig:
		return
	_card_sig = sig
	_card.visible = show_help
	if not show_help:
		return
	if sig == 256:
		_card.show_keys(_rocket_keys())
	elif sig == 64:
		_card.show_keys(_conn_keys())
	elif sig & 1 != 0:
		_card.show_keys(_ship_keys())
	elif sig == 8:
		_card.show_keys(_tank_keys())
	elif sig == 16:
		_card.show_keys(_foot_keys())
	else:
		_card.show_keys(_air_keys())
