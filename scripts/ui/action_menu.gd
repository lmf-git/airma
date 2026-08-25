class_name ActionMenu
extends Control
## TAB context menu. The list is rebuilt from the aircraft state each time it
## opens, so it only ever offers things you can actually do right now.

signal chose(id: String)

const W := 330.0
const ROW := 34.0

var jet: Aircraft = null
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
func open_for_vehicle(v: Node) -> void:
	jet = null
	vehicle = v
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
	jet = a
	vehicle = null
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
	if jet == null or not is_instance_valid(jet):
		return out
	if jet._model.has("hook"):
		out.append({"id": "hook", "label": "Tailhook",
			"note": "DOWN" if jet.hook_down else "UP"})
	var internal: bool = jet.bays.values().any(func(b): return b["kind"] == "internal")
	if internal:
		out.append({"id": "bay", "label": "Weapon bay",
			"note": "OPEN" if jet.any_bay_open() else "SHUT"})
	out.append({"id": "gear", "label": "Landing gear",
		"note": "DOWN" if jet.gear_down else "UP"})
	out.append({"id": "flaps", "label": "Flaps",
		"note": "DOWN" if jet.flaps > 0.5 else "UP"})
	if jet.has_canopy():
		out.append({"id": "canopy", "label": "Canopy",
			"note": "OPEN" if jet.canopy_open else "SHUT"})
	if jet.has_hold():
		out.append({"id": "ramp", "label": "Cargo ramp",
			"note": "OPEN" if jet.ramp_open else "SHUT"})
	out.append({"id": "fbw", "label": "Fly-by-wire",
		"note": "ON" if jet.assist else "OFF"})
	if jet.on_ground and jet.linear_velocity.length() < 1.5:
		out.append({"id": "dismount", "label": "Climb out", "note": ""})
	if jet.spec.get("gunship", false):
		out.append({"id": "gunner", "label": "Gunner station", "note": "G"})
	out.append({"id": "eject", "label": "Eject", "note": "!"})
	return out

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
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
	items = _build()
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
	draw_string(_font, org + Vector2(14, 26), "AIRCRAFT ACTIONS", HORIZONTAL_ALIGNMENT_LEFT,
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
