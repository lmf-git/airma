class_name ActionMenu
extends Control
## TAB context menu. The list is rebuilt from the aircraft state each time it
## opens, so it only ever offers things you can actually do right now.

signal chose(id: String)

const W := 330.0
const ROW := 34.0

var aircraft: Aircraft = null
var items: Array = []          # [{id, label, note}]
var index := 0
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)

var vehicle: Node = null          # a tank or a ship, when that is what you are in

## Open on whatever the player is actually crewing. A tank captain has no use
## for a tailhook and a ship has no bays: showing an aeroplane's actions from
## the bridge was simply the wrong menu.
## Which page is up, so that choosing something rebuilds the list it came from.
## `_fire` rebuilt the aircraft page whatever you were in, so picking an action
## in a tank emptied the menu.
var _page := "air"

## On foot. There is no vehicle and no aeroplane, but there is still something
## to command: what is in orbit. Without this, TAB did nothing at all once you
## climbed out, and the satellite terminal was unreachable on foot.
func open_for_foot() -> void:
	aircraft = null
	vehicle = null
	_page = "foot"
	items = _build_foot()
	index = 0
	visible = not items.is_empty()
	set_process(visible)
	queue_redraw()

func _build_foot() -> Array:
	var out: Array = []
	var sats: int = Sim.census("satellites")
	if sats > 0:
		out.append({"id": "satlink", "label": "Satellite terminal",
			"note": Sim.coverage_source(0)})
		out.append({"id": "asattgt", "label": "Assign ASAT target",
			"note": Sim.label_of(Sim.sat_target)
				if is_instance_valid(Sim.sat_target) else "none"})
	else:
		out.append({"id": "satlink", "label": "Satellite terminal",
			"note": "nothing in orbit"})
	if Sim.objective != Vector3.INF:
		out.append({"id": "objclear", "label": "Clear the objective marker",
			"note": "set"})
	return out

func open_for_vehicle(v: Node) -> void:
	aircraft = null
	vehicle = v
	_page = "vehicle"
	items = _build_vehicle()
	index = 0
	visible = not items.is_empty()
	set_process(visible)
	queue_redraw()

func _build_vehicle() -> Array:
	var out: Array = []
	if vehicle == null or not is_instance_valid(vehicle):
		return out
	if vehicle is Ship:
		var sh := vehicle as Ship
		out.append({"id": "sensor", "label": "Sensor page", "note": "O"})
		out.append({"id": "allstop", "label": "All stop",
			"note": "%.0f%%" % (sh.telegraph * 100.0)})
		out.append({"id": "amidships", "label": "Helm amidships",
			"note": "%+0.2f" % sh.helm})
		out.append({"id": "dismount", "label": "Hand over the conn", "note": "U"})
		return out
	var tk := vehicle as Tank
	if tk != null:
		out.append({"id": "sensor", "label": "Commander's sight", "note": "O"})
	if tk == null:
		return out
	out.append({"id": "weapon", "label": "Weapon", "note": tk.weapon_label()})
	if tk.is_indirect():
		out.append({"id": "map", "label": "Map fire mission", "note": "M"})
		out.append({"id": "clearfm", "label": "Cancel fire mission",
			"note": "set" if tk.map_target != Vector3.INF else "none"})
	out.append({"id": "gunner", "label": "Gunner sight",
		"note": "ON" if tk.gunner else "OFF"})
	out.append({"id": "dismount", "label": "Get out", "note": "U"})
	return out

func open_for(a: Aircraft) -> void:
	aircraft = a
	vehicle = null
	_page = "air"
	items = _build()
	index = 0
	visible = not items.is_empty()
	set_process(visible)
	queue_redraw()

func close() -> void:
	visible = false
	set_process(false)

func _build() -> Array:
	var out: Array = []
	if aircraft == null or not is_instance_valid(aircraft):
		return out
	if aircraft._model.has("hook"):
		out.append({"id": "hook", "label": "Tailhook",
			"note": "DOWN" if aircraft.hook_down else "UP"})
	var internal: bool = aircraft.bays.values().any(func(b): return b["kind"] == "internal")
	if internal:
		out.append({"id": "bay", "label": "Weapon bay",
			"note": "OPEN" if aircraft.any_bay_open() else "SHUT"})
	out.append({"id": "gear", "label": "Landing gear",
		"note": "DOWN" if aircraft.gear_down else "UP"})
	out.append({"id": "flaps", "label": "Flaps",
		"note": "DOWN" if aircraft.flaps > 0.5 else "UP"})
	if aircraft.has_canopy():
		out.append({"id": "canopy", "label": "Canopy",
			"note": "OPEN" if aircraft.canopy_open else "SHUT"})
	if aircraft.has_hold():
		out.append({"id": "ramp", "label": "Cargo ramp",
			"note": "OPEN" if aircraft.ramp_open else "SHUT"})
	out.append({"id": "fbw", "label": "Fly-by-wire",
		"note": "ON" if aircraft.assist else "OFF"})
	# Autopilot. Hold what you have, or orbit where you are — and which way
	# round, because a drone watching a sector wants to be on one side of it.
	# A helicopter gets the hover instead of the aeroplane's altitude hold: it
	# is a different thing, it holds a place rather than a height.
	if aircraft is PlayerHeli:
		out.append({"id": "hover", "label": "Auto hover",
			"note": "ON" if (aircraft as PlayerHeli).hover_hold else "OFF"})
	out.append({"id": "aphold", "label": "Autopilot: hold altitude",
		"note": "ON" if aircraft.ap_mode == "hold" else "OFF"})
	out.append({"id": "aploiter", "label": "Autopilot: loiter",
		"note": "ON" if aircraft.ap_mode == "loiter" else "OFF"})
	if Sim.objective != Vector3.INF:
		out.append({"id": "apgoto", "label": "Autopilot: fly to objective",
			"note": "ON" if aircraft.ap_mode == "goto" else "OFF"})
	if aircraft.ap_mode == "loiter":
		out.append({"id": "apturn", "label": "Orbit direction",
			"note": "RIGHT" if aircraft.ap_turn > 0.0 else "LEFT"})
	# Lighting. Both lamps were switched from the keyboard only, and the
	# navigation lights not at all -- so going dark before a night ingress
	# meant there was nothing to press.
	# The satellite terminal. Only offered when there is actually something
	# overhead to talk to.
	if Sim.census("satellites") > 0:
		out.append({"id": "satlink", "label": "Satellite terminal",
			"note": Sim.coverage_source(aircraft.team if "team" in aircraft else 0)})
	out.append({"id": "jammer", "label": "Jammer",
		"note": "ON" if aircraft.jammer else "OFF"})
	out.append({"id": "nav", "label": "Nav lights",
		"note": "ON" if aircraft.nav_on else "OFF"})
	out.append({"id": "lamp", "label": "Landing lamp",
		"note": "ON" if aircraft.lights_on else "OFF"})
	if aircraft.on_ground and aircraft.linear_velocity.length() < 1.5:
		out.append({"id": "dismount", "label": "Climb out", "note": ""})
	if aircraft.spec.get("gunship", false):
		out.append({"id": "gunner", "label": "Gunner station", "note": "G"})
	out.append({"id": "eject", "label": "Eject", "note": "!"})
	return out

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	# Nothing to steer through when the menu is shut, and it is shut whenever
	# the list came out empty — which is when `% items.size()` was a modulo by
	# zero. The panel goes on receiving unhandled input either way.
	if not visible or items.is_empty():
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_DOWN or k == KEY_S:
			index = (index + 1) % items.size()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif k == KEY_UP or k == KEY_W:
			index = (index - 1 + items.size()) % items.size()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			_fire()
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k < KEY_1 + items.size():
			index = k - KEY_1
			_fire()
			get_viewport().set_input_as_handled()

func _fire() -> void:
	if index < items.size():
		chose.emit(items[index]["id"])
	# Rebuild the page you are actually on.
	match _page:
		"vehicle":
			items = _build_vehicle()
		"foot":
			items = _build_foot()
		_:
			items = _build()
	index = clampi(index, 0, maxi(items.size() - 1, 0))
	queue_redraw()

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not visible or items.is_empty():
		return
	var vp := get_viewport_rect().size
	var h := ROW * items.size() + 44.0
	var org := Vector2(vp.x * 0.5 - W * 0.5, vp.y * 0.5 - h * 0.5)
	draw_rect(Rect2(org, Vector2(W, h)), Color(0.03, 0.06, 0.08, 0.88), true)
	draw_rect(Rect2(org, Vector2(W, h)), Color(0.35, 0.95, 0.55, 0.8), false, 1.6)
	var title := "AIRCRAFT ACTIONS"
	if _page == "vehicle":
		title = "VEHICLE ACTIONS"
	elif _page == "foot":
		title = "ORBITAL COMMAND"
	draw_string(_font, org + Vector2(14, 26), title, HORIZONTAL_ALIGNMENT_LEFT,
		-1, 15, Color(0.5, 0.95, 0.65))
	for i in items.size():
		var y := org.y + 44.0 + i * ROW
		var sel := i == index
		if sel:
			draw_rect(Rect2(Vector2(org.x + 6, y - 20), Vector2(W - 12, ROW - 4)),
				Color(0.25, 0.85, 0.5, 0.20), true)
		var col := Color(1.0, 0.95, 0.75) if sel else Color(0.80, 0.88, 0.92)
		draw_string(_font, Vector2(org.x + 16, y), "%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 15, Color(0.55, 0.8, 0.95))
		draw_string(_font, Vector2(org.x + 40, y), str(items[i]["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		draw_string(_font, Vector2(org.x + W - 92, y), str(items[i]["note"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 1.0, 0.65))
	draw_string(_font, org + Vector2(14, h - 10), "W/S move   ENTER select   TAB close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.7, 0.8))
