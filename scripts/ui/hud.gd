class_name HUD
extends Control
## World-referenced head-up display: the pitch ladder, flight-path marker and
## target boxes are unprojected through the live camera, so they stay glued to
## the world in every view.

const GREEN := Color(0.24, 1.0, 0.42)
const DIM := Color(0.30, 1.0, 0.48, 0.70)
const AMBER := Color(1.0, 0.78, 0.22)
const RED := Color(1.0, 0.32, 0.28)
const WHITE := Color(0.92, 0.96, 1.0)
const PANEL_NAMES := ["off", "sensor", "radar", "minimap"]

var jet: Aircraft = null
var _ccip_p := Vector3.INF
var _ccip_t := 0
var flight_page := true          # false from an outside camera: see world.gd
var walker: Node = null
var carrier: Carrier = null
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

func _on_event(text: String, kind: int) -> void:
	log_lines.push_front({"t": text, "k": kind, "age": 0.0})
	if log_lines.size() > 6:
		log_lines.resize(6)

func _process(delta: float) -> void:
	_t += delta
	for l in log_lines:
		l["age"] += delta
	queue_redraw()

func _txt(pos: Vector2, s: String, pt := 15, col := GREEN, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(_font, pos, s, align, w, pt, col)

func _box(r: Rect2, col := GREEN, width := 1.0) -> void:
	draw_rect(r, col, false, width)

func _draw() -> void:
	# The key card belongs on every page. It was drawn at the end of the
	# aeroplane one, and every other page returns before it gets there — so F2
	# did nothing at all on a bridge, in a driver's seat or on foot, and the
	# only place the keys appeared was the event log.
	if carrier != null and is_instance_valid(carrier):
		_draw_conn()
		if show_help:
			_draw_help()
		return
	if ship != null and is_instance_valid(ship):
		_draw_bridge()
		if show_help:
			_draw_help()
		return
	if tank != null and is_instance_valid(tank):
		_draw_driver()
		if show_help:
			_draw_help()
		return
	if walker != null and is_instance_valid(walker):
		_draw_on_foot()
		if show_help:
			_draw_help()
		return
	if jet == null or not is_instance_valid(jet) or cam == null:
		return
	if not flight_page:
		# outside the aeroplane: no glass in front of you, no symbology on it,
		# but warnings and the event log still belong on screen
		var vpo := get_viewport_rect().size
		_draw_log(vpo)
		if ("msg_t" in jet) and jet.msg_t > 0.0:
			_txt(Vector2(0, vpo.y - 176.0), String(jet.msg).to_upper(), 19, WHITE,
				HORIZONTAL_ALIGNMENT_CENTER, vpo.x)
		return
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	var alive := jet.alive

	_setup_hud_box()
	if alive:
		if _hud_clip:
			_draw_hud_glass()
		_draw_ladder()
		_draw_fpm()
		_draw_targets()
		_draw_bomb_cue()
	_draw_left(vp)
	_draw_right(vp)
	_draw_heading(vp)
	_draw_status(vp)
	_draw_panels(vp)
	_draw_landing(vp)
	_draw_warnings(vp, c)
	_draw_log(vp)
	if mode != null and is_instance_valid(mode):
		_draw_mode(vp)
	if show_help:
		_draw_help()

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

func _draw_world_contacts(src: Node3D, eye: Camera3D) -> void:
	if not is_instance_valid(src) or not is_instance_valid(eye):
		return
	var my_team: int = int(src.team) if ("team" in src) else -1
	var held: Node = src.get("ai_target") if ("ai_target" in src) else null
	var reach: float = maxf(Sim.radar_range(), 26000.0)
	var vp := get_viewport_rect().size
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == src or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if n.is_in_group("no_lock"):
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
	_txt(Vector2(26, vp.y - 30.0), "%s  %s" % [ship.weapon_label(), state], 16,
		g if state == "READY" else AMBER)
	# and what it is laid on, which is the whole point of having a sensor
	if is_instance_valid(ship.ai_target):
		var td: float = ship.global_position.distance_to(ship.ai_target.global_position)
		_txt(Vector2(26, vp.y - 6.0), "LAID ON %s  %.1f km" % [
			Sim.label_of(ship.ai_target).to_upper(), td * 0.001], 15, AMBER)
	var c := vp * 0.5
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
	_draw_world_contacts(tank, cam)
	var c := vp * 0.5
	var g := Color(0.55, 1.0, 0.62)
	draw_line(c - Vector2(30, 0), c - Vector2(8, 0), g, 1.5)
	draw_line(c + Vector2(8, 0), c + Vector2(30, 0), g, 1.5)
	draw_line(c - Vector2(0, 30), c - Vector2(0, 8), g, 1.5)
	draw_line(c + Vector2(0, 8), c + Vector2(0, 30), g, 1.5)
	if tank.gunner:
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

## Minimal symbology while you are walking the ramp.
func _draw_on_foot() -> void:
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	draw_arc(c, 3.0, 0, TAU, 10, Color(1, 1, 1, 0.5), 1.5)
	var p: String = walker.prompt()
	if p != "":
		var w := 420.0
		draw_rect(Rect2(c.x - w * 0.5, c.y + 90.0, w, 40.0), Color(0.02, 0.05, 0.07, 0.6), true)
		_box(Rect2(c.x - w * 0.5, c.y + 90.0, w, 40.0), AMBER, 1.4)
		_txt(Vector2(c.x - w * 0.5, c.y + 116.0), p, 19, AMBER, HORIZONTAL_ALIGNMENT_CENTER, w)
	var amm: int = walker.ammo
	var rel: float = walker.reloading
	_txt(Vector2(26, vp.y - 132.0), "AMMO %d / %d%s" % [amm, walker.MAG,
		"   RELOADING" if rel > 0.0 else ""], 19,
		RED if (amm <= 5 or rel > 0.0) else GREEN)
	_txt(Vector2(26, vp.y - 106.0), "HEALTH %d" % int(maxf(walker.health, 0.0)), 17,
		RED if walker.health < 40.0 else GREEN)
	_txt(Vector2(26, vp.y - 76.0), "WASD walk   SHIFT run   CTRL crouch   SPACE jump   V fire   C view   U board", 15,
		Color(0.85, 0.92, 1.0))
	_draw_log(vp)

## Work out where the combiner glass sits on screen this frame.
func _setup_hud_box() -> void:
	var vp := get_viewport_rect().size
	_hud_clip = false
	if cam == null or not is_instance_valid(cam) or jet == null:
		return
	# only in the cockpit: from outside, the symbology is an overlay
	if not (cam is ChaseCamera) or (cam as ChaseCamera).mode != ChaseCamera.Mode.COCKPIT:
		return
	var bore: Vector3 = cam.global_position + (-jet.global_transform.basis.z) * 900.0
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
	var p: Vector3 = jet.global_position
	var v: Vector3 = jet.linear_velocity
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
	var w: String = jet.current_weapon()
	if w == "gun" or String(WeaponSpec.get_spec(w)["kind"]) != "bomb":
		return
	var aim := Vector3.INF
	var label := ""
	if jet.designated != Vector3.INF:
		aim = jet.designated
		label = "LASER"
	elif jet.target != null and is_instance_valid(jet.target):
		aim = (jet.target as Node3D).global_position
		label = Sim.label_of(jet.target).left(16).to_upper()
	if aim != Vector3.INF and cam.is_position_behind(aim) == false:
		var a := _project(aim)
		# a diamond on the designated point
		var r := 13.0
		_hud_line(a + Vector2(0, -r), a + Vector2(r, 0), AMBER, 2.0)
		_hud_line(a + Vector2(r, 0), a + Vector2(0, r), AMBER, 2.0)
		_hud_line(a + Vector2(0, r), a + Vector2(-r, 0), AMBER, 2.0)
		_hud_line(a + Vector2(-r, 0), a + Vector2(0, -r), AMBER, 2.0)
		_txt(a + Vector2(r + 5, 5), label, 13, AMBER)
		var d: float = jet.global_position.distance_to(aim)
		_txt(a + Vector2(r + 5, 21), "%.1f km" % (d * 0.001), 13, AMBER)
		# Whether the shot is actually on. A box and a range with nothing else
		# beside them reads as "cleared to release", and for an unpowered bomb
		# that is often a lie — it says the weapon failed when in truth the
		# aeroplane was never in a position to take the shot.
		var why := jet.shot_blocked(jet.current_weapon(), jet.target) \
			if is_instance_valid(jet.target) else ""
		if why != "":
			_txt(a + Vector2(r + 5, 37), why, 13, RED)
		elif jet.locked:
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
	var b := jet.global_transform.basis
	var fwd := -b.z
	var head := Vector3(fwd.x, 0.0, fwd.z)
	if head.length_squared() < 0.001:
		head = Vector3(b.y.x, 0.0, b.y.z)
	head = head.normalized()
	var rt := head.cross(Vector3.UP).normalized() * -1.0
	var cp := cam.global_position
	const D := 900.0
	for p in range(-80, 85, 5):
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
		if s1.distance_to(s2) > get_viewport_rect().size.x * 3.0:
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
	var v := jet.linear_velocity
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
	var bs := cam.global_position + (-jet.global_transform.basis.z) * 900.0
	if _visible_pt(bs):
		var g := _project(bs)
		draw_line(g - Vector2(14, 0), g - Vector2(5, 0), WHITE, 1.4)
		draw_line(g + Vector2(5, 0), g + Vector2(14, 0), WHITE, 1.4)
		draw_line(g - Vector2(0, 14), g - Vector2(0, 5), WHITE, 1.4)

func _draw_targets() -> void:
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == jet:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var hostile: bool = ("team" in n) and int(n.team) != jet.team
		var p: Vector3 = n.global_position
		if not _visible_pt(p):
			continue
		var d := jet.global_position.distance_to(p)
		# Reach follows the radar setting rather than a fixed 26 km. Shipping
		# sits twenty-odd kilometres offshore and was falling off the edge of
		# the old limit, so a warship you had locked simply had no box on it.
		if d > maxf(Sim.radar_range(), 26000.0):
			continue
		var s := _project(p)
		if not _in_hud(s):
			continue
		var r: float = clampf(900.0 / maxf(d, 1.0), 6.0, 40.0)
		var col := RED if hostile else Color(0.4, 0.75, 1.0)
		# A contact behind a ridge still shows -- the radar can see it -- but
		# the box goes dashed so you know you have no line of sight to it.
		var clear := _los_clear(jet.global_position, p)
		if n == jet.target:
			col = AMBER
			var q := r + 9.0
			draw_line(s + Vector2(-q, -q), s + Vector2(-q + 8, -q), col, 2.0)
			draw_line(s + Vector2(-q, -q), s + Vector2(-q, -q + 8), col, 2.0)
			draw_line(s + Vector2(q, q), s + Vector2(q - 8, q), col, 2.0)
			draw_line(s + Vector2(q, q), s + Vector2(q, q - 8), col, 2.0)
			_txt(s + Vector2(q + 6, -2), "%.1fkm" % (d * 0.001), 13, col)
			_txt(s + Vector2(q + 6, 14), "%d kt" % int(_kt(n)), 12, col)
			if jet.locked:
				# The same question the release cue asks. This one said LOCK
				# whenever the radar was holding something, whatever was on the
				# rail: a Maverick that cannot reach ten kilometres showed LOCK
				# on a target twenty away and went in the dirt.
				var stop := jet.shot_blocked(jet.current_weapon(), n)
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
	var kias := jet.ias * 1.94384
	_box(Rect2(x - 4, y - 15, 92, 30), GREEN, 1.4)
	_txt(Vector2(x + 84, y + 7), "%d" % int(kias), 20, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 84)
	_txt(Vector2(x - 4, y - 24), "KIAS", 12, DIM)
	_txt(Vector2(x - 4, y + 34), "M %.2f" % jet.mach, 15, GREEN)
	_txt(Vector2(x - 4, y + 54), "G %+.1f" % jet.g_load, 15,
		RED if absf(jet.g_load) > jet.spec["g_limit"] else GREEN)
	# the peak sits alongside so you can see what the pull actually cost
	_txt(Vector2(x - 4, y + 70), "MAX %+.1f  MIN %+.1f" % [jet.g_peak, jet.g_min], 12,
		AMBER if jet.g_peak > jet.spec["g_limit"] else GREEN)
	if jet.g_strain > 0.05:
		_txt(Vector2(x - 4, y + 86), "GREY-OUT", 13, RED if jet.g_strain > 0.5 else AMBER)
	elif jet.g_red > 0.05:
		_txt(Vector2(x - 4, y + 86), "RED-OUT", 13, RED if jet.g_red > 0.5 else AMBER)
	_txt(Vector2(x - 4, y + 74), "AOA %.1f" % rad_to_deg(jet.aoa), 15,
		AMBER if jet.stalling else GREEN)
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
	var alt := jet.global_position.y * 3.28084
	_box(Rect2(x, y - 15, 104, 30), GREEN, 1.4)
	_txt(Vector2(x + 98, y + 7), "%d" % int(alt), 20, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 96)
	_txt(Vector2(x, y - 24), "ALT FT MSL", 12, DIM)
	var agl := jet.agl * 3.28084
	_txt(Vector2(x, y + 34), "R %d" % int(agl), 15, AMBER if agl < 500.0 else GREEN)
	_txt(Vector2(x, y + 54), "VS %+d" % int(jet.vspeed * 196.85), 15,
		RED if jet.vspeed * 196.85 < -2200.0 else GREEN)
	# vertical speed bar
	var bx := x - 26.0
	draw_line(Vector2(bx, y - 110), Vector2(bx, y + 110), DIM, 1.2)
	var vsn := clampf(jet.vspeed / 60.0, -1.0, 1.0)
	draw_line(Vector2(bx - 7, y - vsn * 110.0), Vector2(bx + 7, y - vsn * 110.0), GREEN, 2.4)

func _draw_heading(vp: Vector2) -> void:
	var b := jet.global_transform.basis
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
	var t := jet.throttle
	draw_rect(Rect2(x + 2, y + h - 2 - (h - 4) * t, 12, (h - 4) * t),
		AMBER if t > 0.78 else GREEN)
	draw_line(Vector2(x - 4, y + h * (1.0 - 0.78)), Vector2(x + 20, y + h * (1.0 - 0.78)), AMBER, 1.0)
	_txt(Vector2(x - 6, y + h + 16), "THR", 13, DIM)
	_txt(Vector2(x - 6, y + h + 32), "%d%%" % int(t * 100.0), 14, GREEN)
	# An aeroplane with no reheat has no "AB" band: past the military stop it is
	# simply at maximum, and labelling it otherwise on an A-10 or a Hercules is
	# telling the pilot about a gate that is not there.
	var reheat: bool = jet != null and float(jet.spec.get("thrust_ab", 0.0)) \
		> float(jet.spec.get("thrust_mil", 1.0)) * 1.04
	var hot: bool = t > 0.78
	var word := ("AB" if reheat else "MAX") if hot else "MIL"
	_txt(Vector2(x - 2, y - 6), word, 13, AMBER if (hot and reheat) else DIM)
	# fuel
	var fx := x + 52.0
	var fr: float = jet.fuel / maxf(jet.spec["fuel"], 1.0)
	_box(Rect2(fx, y, 16, h), DIM, 1.2)
	draw_rect(Rect2(fx + 2, y + h - 2 - (h - 4) * fr, 12, (h - 4) * fr),
		RED if fr < 0.12 else GREEN)
	_txt(Vector2(fx - 6, y + h + 16), "FUEL", 13, DIM)
	_txt(Vector2(fx - 6, y + h + 32), "%d" % int(jet.fuel), 14, RED if fr < 0.12 else GREEN)

	# gear / flaps / brakes
	var sx := vp.x * 0.5 - 130.0
	var sy := vp.y - 116.0
	var items := [
		["GEAR", jet.gear_anim > 0.99, jet.gear_anim > 0.01 and jet.gear_anim < 0.99],
		["FLAP", jet.flap_anim > 0.5, false],
		["BRK", jet.wheel_brake or jet.airbrake, false],
		["FBW", jet.assist, false],
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
	var total := cell_w * float(jet.weapon_types.size())
	var sxx := vp.x * 0.5 - total * 0.5
	for i in jet.weapon_types.size():
		var w: String = jet.weapon_types[i]
		var sel: bool = i == jet.selected
		var label: String = jet.weapon_label(w)
		var count: int = jet.weapon_count(w)
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
	var has_bays: bool = jet.bays.values().any(func(b): return b["kind"] == "internal")
	var bx2 := vp.x * 0.5 - total * 0.5 - 178.0
	if has_bays:
		var bay_open := jet.any_bay_open()
		var bcol := AMBER if bay_open else DIM
		_box(Rect2(bx2, strip_y, 168.0, 46.0), bcol, 2.0 if bay_open else 1.0)
		_txt(Vector2(bx2 + 8, strip_y + 20), "B", 17, bcol)
		_txt(Vector2(bx2 + 28, strip_y + 20), "BAY " + ("OPEN" if bay_open else "SHUT"), 16, bcol)
		_draw_bay_icon(Vector2(bx2 + 118, strip_y + 34), bcol)
		if not bay_open and jet.current_weapon() != "gun":
			_txt(Vector2(bx2 + 28, strip_y + 39), "open to fire", 13, RED)
	else:
		_box(Rect2(bx2, strip_y, 168.0, 46.0), DIM, 1.0)
		_txt(Vector2(bx2 + 10, strip_y + 20), "EXTERNAL PYLONS", 14, DIM)
		_txt(Vector2(bx2 + 10, strip_y + 39), "always ready", 13, DIM)
	# stores rack + flares to the right of the strip
	var rx := vp.x * 0.5 + total * 0.5 + 16.0
	_txt(Vector2(rx, strip_y + 16), "STORES", 13, DIM)
	var px := rx
	for st in jet.stores:
		var col2 := DIM if st["gone"] else GREEN
		draw_rect(Rect2(px, strip_y + 24, 9, 18), col2, not st["gone"])
		if st["gone"]:
			_box(Rect2(px, strip_y + 24, 9, 18), col2, 1.0)
		px += 13.0
	_txt(Vector2(rx, strip_y + 58), "N  FLARE %d" % jet.flares, 14,
		GREEN if jet.flares > 24 else AMBER)
	_txt(Vector2(rx, strip_y + 76), "B  CHAFF %d" % jet.chaff, 14,
		GREEN if jet.chaff > 24 else AMBER)

func _draw_bay_icon(at: Vector2, col: Color) -> void:
	var open := 0.0
	for k in jet.bays:
		open = maxf(open, jet.bays[k]["anim"] if jet.bays[k]["kind"] == "internal" else 0.0)
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
				_draw_radar_at(slot[1], 78.0)
			3:
				_draw_minimap_at(slot[1], 82.0)
			1:
				_draw_sensor_stub(slot[1], 82.0)

## Compass rose minimap: contacts and the runway, oriented to your nose.
func _draw_minimap_at(c: Vector2, r: float) -> void:
	var rng: float = Sim.radar_range() * 0.35
	draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Color(0.02, 0.05, 0.04, 0.5), true)
	_box(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), DIM, 1.2)
	var b := jet.global_transform.basis
	var hdg := atan2(-b.z.x, b.z.z)
	var here := Vector2(jet.global_position.x, jet.global_position.z)
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
	for z in get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		var col := Color(0.35, 0.75, 1.0) if z.owner_team == 0 else (
			RED if z.owner_team == 1 else Color(0.8, 0.8, 0.8))
		var zp: Vector2 = to_screen.call(Vector2(z.global_position.x, z.global_position.z))
		draw_circle(zp, 3.0, col)
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == jet:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var p: Vector2 = to_screen.call(Vector2(n.global_position.x, n.global_position.z))
		if (p - c).length() > r:
			continue
		var hostile: bool = ("team" in n) and n.team != jet.team
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
		else (jet.global_position if is_instance_valid(jet) else Vector3.ZERO)

func _scope_basis() -> Basis:
	return _scope_src.global_transform.basis if is_instance_valid(_scope_src) \
		else (jet.global_transform.basis if is_instance_valid(jet) else Basis())

func _scope_team() -> int:
	if is_instance_valid(_scope_src) and "team" in _scope_src:
		return int(_scope_src.team)
	return int(jet.team) if is_instance_valid(jet) else 0

func _scope_target() -> Node:
	if is_instance_valid(_scope_src):
		return _scope_src.ai_target if "ai_target" in _scope_src else null
	return jet.target if is_instance_valid(jet) else null

func _draw_radar_at(c: Vector2, r: float) -> void:
	for k in _held.keys():
		if not is_instance_valid(k) or _t - float(_held[k]) > 10.0:
			_held.erase(k)
	draw_arc(c, r, 0, TAU, 40, DIM, 1.2)
	draw_arc(c, r * 0.5, 0, TAU, 30, Color(DIM.r, DIM.g, DIM.b, 0.25), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(DIM.r, DIM.g, DIM.b, 0.25), 1.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(DIM.r, DIM.g, DIM.b, 0.25), 1.0)
	_txt(c + Vector2(-r, r + 16), "RWR  %d km   [ ] panels   - = range" % int(Sim.radar_range() * 0.001), 12, DIM)
	var b := _scope_basis()
	var origin := _scope_origin()
	var my_team := _scope_team()
	var my_target := _scope_target()
	var fwd := -b.z
	var hdg := atan2(fwd.x, -fwd.z)
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == _scope_src or n == jet:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if n.is_in_group("no_lock"):
			continue
		var rel: Vector3 = n.global_position - origin
		var d := rel.length()
		if d > Sim.radar_range():
			continue
		var bearing := atan2(rel.x, -rel.z) - hdg
		var rr := r * clampf(d / Sim.radar_range(), 0.0, 1.0)
		var p := c + Vector2(sin(bearing), -cos(bearing)) * rr
		var hostile: bool = ("team" in n) and int(n.team) != my_team
		var col := RED if hostile else Color(0.4, 0.8, 1.0)
		# Terrain masking, on the scope as well as on the lock. A contact behind
		# a ridge is not a return; painting it solid and then refusing to lock
		# it is worse than not painting it, because the pilot can see it and
		# cannot understand why the radar will not take it.
		var masked := d > 2000.0 and not Sim.line_of_sight(
			origin + Vector3(0, 4, 0),
			(n as Node3D).global_position + Vector3(0, 4, 0), 250.0)
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
	# Rounds in the air. Yours flash blue, anything tracking you flashes red.
	#
	# The old test was `m.target != _scope_src and m.target != jet`, and in an
	# aeroplane `_scope_src` is null — so any round with no target at all
	# compared null to null, failed the test and was painted as an inbound
	# threat. Your own bombs, and any missile that had lost its lock, blinked
	# red on the scope as though they were coming for you.
	var me: Node = _scope_src if is_instance_valid(_scope_src) else jet
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

# ---------------------------------------------------------------- landing aid
func _draw_landing(vp: Vector2) -> void:
	if base == null:
		return
	var p := jet.global_position
	var aim := Vector3(0, 0, Airbase.AIM_Z)
	var to_36 := p.z > Airbase.AIM_Z
	var d := Vector2(p.x - aim.x, p.z - aim.z).length()
	if not (jet.gear_down and d < 18000.0 and jet.agl < 3000.0):
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
	if jet.on_ground and Sim.on_runway(p.x, p.z):
		var heading_north: bool = (-jet.global_transform.basis.z).z < 0.0
		var rem: float = (p.z + Sim.RUNWAY_LEN * 0.5) if heading_north else (Sim.RUNWAY_LEN * 0.5 - p.z)
		_txt(Vector2(cx - 60, cy + half + 46), "REMAINING %d m" % int(rem), 15,
			RED if rem < 400.0 else GREEN)

# ---------------------------------------------------------------- warnings
func _draw_warnings(vp: Vector2, c: Vector2) -> void:
	var blink := fmod(_t, 0.6) < 0.35
	var y := c.y - 150.0
	if not jet.alive:
		_txt(Vector2(0, c.y - 40), "AIRCRAFT DESTROYED", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		_txt(Vector2(0, c.y + 6), "ESC for the menu", 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		return
	if jet.missile_warn > 0.0 and blink:
		_txt(Vector2(0, y), "MISSILE  —  BREAK AND FLARE", 26, RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 34.0
	if jet.stalling and blink:
		_txt(Vector2(0, y), "STALL", 24, AMBER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 30.0
	if jet.agl < 150.0 and jet.vspeed < -12.0 and not jet.gear_down and blink:
		_txt(Vector2(0, y), "PULL UP", 26, RED, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 30.0
	if jet.fuel < jet.spec["fuel"] * 0.1 and blink:
		_txt(Vector2(0, y), "BINGO FUEL", 20, AMBER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		y += 26.0
	if jet.health < 55.0:
		_txt(Vector2(0, y), "DAMAGE %d%%" % int(100.0 - jet.health), 20,
			RED if jet.health < 30.0 else AMBER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	if ("msg_t" in jet) and jet.msg_t > 0.0:
		_txt(Vector2(0, vp.y - 176.0), String(jet.msg).to_upper(), 19, WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x)

func _draw_log(vp: Vector2) -> void:
	var y := 90.0
	for l in log_lines:
		var a: float = clampf(1.0 - (l["age"] - 5.0) / 2.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var col: Color = [WHITE, GREEN, RED][int(l["k"])]
		col.a = a
		_txt(Vector2(vp.x - 300.0, y), str(l["t"]), 14, col)
		y += 19.0

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
func _draw_mode(vp: Vector2) -> void:
	var st: Dictionary = mode.hud_state()
	var cx := vp.x * 0.5
	var y := 96.0
	var name_map := {"conquest": "CONQUEST", "rush": "RUSH", "warlords": "WARLORDS",
		"tdm": "TEAM DEATHMATCH", "ffa": "FREE FOR ALL"}
	_txt(Vector2(0, y), str(name_map.get(st["mode"], st["mode"])).to_upper(), 15,
		Color(0.7, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	y += 22.0
	if st["mode"] in ["tdm", "ffa"]:
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

func _draw_help() -> void:
	# what the keys do depends on what you are sitting in
	if ship != null and is_instance_valid(ship):
		_help_body(_ship_keys())
		return
	if tank != null and is_instance_valid(tank):
		_help_body(_tank_keys())
		return
	if walker != null and is_instance_valid(walker):
		_help_body(_foot_keys())
		return
	_help_body(_air_keys())

func _ship_keys() -> Array:
	var conn := [
		["A / D", "wheel: port / starboard"],
		["W / S", "telegraph: ahead / astern"],
		["P", "view: conning tower / close / chase / wide"],
		["N", "night vision"],
		["M", "tactical map"],
		["U", "hand over the conn"],
	]
	if ship.can_dive():
		conn.append(["PGDN / PGUP", "dive / surface"])
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
	return [["THE CONN", conn], ["WEAPONS", arms], ["GENERAL", _general_keys()]]

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
			["SHIFT", "run"],
			["CTRL", "crouch"],
			["SPACE", "jump"],
			["V", "fire"],
			["P", "view"],
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
			["C", "flares"],
			["B", "chaff"],
			["LMB / SPACE", "fire selected weapon"],
			["V", "gun burst"],
			["N", "flares"],
			["B", "chaff"],
		]],
		["SENSORS", [
			["RMB or O", "raise / stow the sensor page"],
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

## The card itself. Split out so every page can draw its own list through it.
func _help_body(groups: Array) -> void:
	var x := 26.0
	var y := 118.0
	var panel_h := 0.0
	for g in groups:
		panel_h += 26.0 + float(g[1].size()) * 19.0
	draw_rect(Rect2(x - 14, y - 30, 330, panel_h + 24), Color(0.02, 0.04, 0.06, 0.55), true)
	_box(Rect2(x - 14, y - 30, 330, panel_h + 24), Color(0.4, 0.9, 0.6, 0.35), 1.0)
	for g in groups:
		_txt(Vector2(x, y), str(g[0]), 15, Color(0.45, 0.95, 0.65))
		y += 22.0
		for row in g[1]:
			_txt(Vector2(x + 6, y), str(row[0]), 14, Color(1.0, 0.95, 0.7))
			_txt(Vector2(x + 116, y), str(row[1]), 14, Color(0.82, 0.9, 0.95))
			y += 19.0
		y += 4.0
