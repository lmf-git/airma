class_name AdminMenu
extends Control
## A page for watching the aeroplane fly itself. Call an aircraft in on the
## approach, pick a type, and follow it down: it is the same scripted pilot the
## test harness uses, driven from the game rather than the command line.

signal chose(id: String)

var items: Array = []
var index := 0
var jet_id := "f22"
var following := false
var traffic := 0
var _font: Font

const GREEN := Color(0.55, 1.0, 0.72)
const AMBER := Color(1.0, 0.82, 0.35)
const DIM := Color(0.55, 0.68, 0.62)

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)

func open() -> void:
	items = _build()
	index = 0
	visible = true
	set_process(true)
	queue_redraw()

func close() -> void:
	visible = false
	set_process(false)

func _build() -> Array:
	return [
		{"id": "type", "label": "Aircraft", "note": String(JetSpec.get_spec(jet_id)["name"])},
		{"id": "land", "label": "Call one in to land", "note": "12 km final"},
		{"id": "flight", "label": "Call a flight of three", "note": "line astern"},
		{"id": "takeoff", "label": "Send one off the runway", "note": "rolls and climbs"},
		{"id": "follow", "label": "Camera follows the traffic",
		 "note": "ON" if following else "OFF"},
		{"id": "clear", "label": "Clear the circuit", "note": "%d up" % traffic},
	]

func _process(_dt: float) -> void:
	queue_redraw()

func _input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k := (e as InputEventKey).physical_keycode
	if k == KEY_DOWN:
		index = (index + 1) % items.size()
	elif k == KEY_UP:
		index = (index - 1 + items.size()) % items.size()
	elif k == KEY_LEFT or k == KEY_RIGHT:
		if String(items[index]["id"]) == "type":
			var ids := JetSpec.ids()
			var at := maxi(ids.find(jet_id), 0)
			jet_id = ids[(at + (1 if k == KEY_RIGHT else ids.size() - 1)) % ids.size()]
			items = _build()
	elif k == KEY_ENTER or k == KEY_SPACE or k == KEY_KP_ENTER:
		chose.emit(String(items[index]["id"]))
		items = _build()
	elif k == KEY_F3 or k == KEY_ESCAPE:
		close()
	get_viewport().set_input_as_handled()
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	var w := 520.0
	var h := 62.0 + items.size() * 34.0
	var o := Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.5 - h * 0.5)
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.02, 0.05, 0.07, 0.90), true)
	draw_rect(Rect2(o, Vector2(w, h)), GREEN, false, 1.6)
	draw_string(_font, o + Vector2(18, 30), "AIR TRAFFIC", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, GREEN)
	draw_string(_font, o + Vector2(w - 210, 30), "arrows move   ENTER runs   F3 closes",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	for i in items.size():
		var y := o.y + 58.0 + i * 34.0
		var col := AMBER if i == index else GREEN
		if i == index:
			draw_rect(Rect2(Vector2(o.x + 8, y - 18), Vector2(w - 16, 28)),
				Color(GREEN.r, GREEN.g, GREEN.b, 0.10), true)
		draw_string(_font, Vector2(o.x + 22, y), String(items[i]["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		draw_string(_font, Vector2(o.x + w - 230, y), String(items[i]["note"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
