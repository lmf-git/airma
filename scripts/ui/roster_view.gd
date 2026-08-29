class_name RosterView
extends Control
## Who is in the session, on ESC.
##
## There was no way to see it at all: the mission log announced arrivals and
## departures as they happened and then scrolled away, so thirty seconds into a
## game you had no idea who was connected, what they were flying, or which side
## they were on.

const BACK := Color(0.03, 0.05, 0.08, 0.88)
const ACCENT := Color(0.62, 0.92, 1.0)
const DIM := Color(0.55, 0.66, 0.78)
const BLUE := Color(0.40, 0.78, 1.0)
const RED := Color(1.0, 0.42, 0.36)

var net: NetLink = null
var world: Node = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var vs := size
	var w := minf(vs.x * 0.62, 720.0)
	var rows: Array = net.player_positions() if net != null else []
	var h := 132.0 + float(maxi(rows.size(), 1)) * 30.0
	# Down in the corner: this shares the screen with the pause menu, which sits
	# in the middle of it.
	var x := 40.0
	var y := vs.y - h - 40.0
	draw_rect(Rect2(x, y, w, h), BACK)
	draw_rect(Rect2(x, y, w, h), ACCENT * Color(1, 1, 1, 0.5), false, 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x + 26.0, y + 44.0), "SESSION", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 26, ACCENT)
	var sub := "not connected"
	if net != null and net.active:
		sub = net.status_line() if net.has_method("status_line") else net.status
	draw_string(font, Vector2(x + 26.0, y + 68.0), sub, HORIZONTAL_ALIGNMENT_LEFT,
		-1, 14, DIM)
	var cy := y + 100.0
	for col in [[26.0, "CALLSIGN"], [200.0, "FLYING"], [340.0, "SIDE"],
			[430.0, "WHERE"]]:
		draw_string(font, Vector2(x + float(col[0]), cy), String(col[1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	cy += 8.0
	draw_line(Vector2(x + 20.0, cy), Vector2(x + w - 20.0, cy),
		Color(0.3, 0.4, 0.5), 1.0)
	cy += 22.0
	if rows.is_empty():
		draw_string(font, Vector2(x + 26.0, cy), "nobody else — this is a single seat game right now",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
		return
	for r in rows:
		var e: Dictionary = r
		var col2: Color = BLUE if int(e["team"]) == 0 else RED
		var nm: String = String(e["name"]) + ("  (you)" if bool(e["me"]) else "")
		draw_string(font, Vector2(x + 26.0, cy), nm, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 16, col2)
		draw_string(font, Vector2(x + 200.0, cy), String(e["jet"]).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.82, 0.88, 0.94))
		draw_string(font, Vector2(x + 340.0, cy),
			"BLUE" if int(e["team"]) == 0 else "RED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col2)
		var at: Vector3 = e["at"]
		var where := "—"
		if at != Vector3.INF:
			where = "%+.0f, %+.0f km   %s" % [at.x * 0.001, at.z * 0.001,
				{"air": "airborne", "ground": "driving",
				"foot": "on foot"}.get(String(e["kind"]), "")]
		draw_string(font, Vector2(x + 430.0, cy), where, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 13, Color(0.7, 0.78, 0.86))
		cy += 30.0
