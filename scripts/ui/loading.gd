class_name LoadingScreen
extends Control
## What the window shows while the world is being made.
##
## Generation used to run start to finish inside `World._ready`, which is one
## frame as far as the engine is concerned -- so the window sat black and
## unresponsive for twenty-four seconds and the operating system offered to kill
## it. The phases now hand control back between each other, and this is what
## that time looks like from outside.
##
## It draws itself rather than assembling a tree of Controls: it is a handful of
## rectangles and three lines of text, and it has to be up before anything else
## in the game exists.

const BACK := Color(0.026, 0.042, 0.062)
const ACCENT := Color(0.62, 0.92, 1.0)
const DIM := Color(0.42, 0.55, 0.68)
const BAR_BACK := Color(0.10, 0.16, 0.22)

var phase := "Starting up"
var frac := 0.0
var detail := ""
var _t := 0.0
## Eased, so a phase that finishes in one frame does not make the bar jump.
var _shown := 0.0
var _done := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_t += delta
	_shown = move_toward(_shown, frac, maxf(delta * 0.9, absf(frac - _shown) * delta * 6.0))
	queue_redraw()

## Where the build has got to. `f` is the whole job, not the phase.
func step(what: String, f: float, note := "") -> void:
	phase = what
	frac = clampf(f, 0.0, 1.0)
	detail = note

func finish() -> void:
	_done = true
	frac = 1.0

func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), BACK)
	# A horizon, so the screen reads as sky over ground rather than as a crash.
	var hy: float = vs.y * 0.62
	draw_rect(Rect2(0.0, 0.0, vs.x, hy), Color(0.035, 0.062, 0.095))
	draw_rect(Rect2(0.0, hy, vs.x, vs.y - hy), Color(0.030, 0.040, 0.046))
	draw_line(Vector2(0.0, hy), Vector2(vs.x, hy), Color(0.10, 0.22, 0.30), 1.0)
	var font := ThemeDB.fallback_font
	var cx: float = vs.x * 0.5
	var title := "FLIGHT"
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 54).x
	draw_string(font, Vector2(cx - tw * 0.5, hy - 96.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 54, ACCENT)
	# progress bar
	var bw: float = minf(vs.x * 0.52, 620.0)
	var bx: float = cx - bw * 0.5
	var by: float = hy + 70.0
	draw_rect(Rect2(bx, by, bw, 6.0), BAR_BACK)
	draw_rect(Rect2(bx, by, bw * _shown, 6.0), ACCENT)
	# A moving highlight on the leading edge, which is the only thing on screen
	# that says the process is alive while a slow phase runs.
	if not _done:
		var gw := 46.0
		var gx: float = bx + bw * _shown - gw
		if gx > bx:
			draw_rect(Rect2(gx, by, gw, 6.0),
				Color(1.0, 1.0, 1.0, 0.10 + 0.10 * sin(_t * 4.0)))
	var line: String = phase if not _done else "Ready"
	draw_string(font, Vector2(bx, by - 16.0), line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.82, 0.90, 0.97))
	var pct := "%d%%" % int(round(_shown * 100.0))
	var pw := font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(font, Vector2(bx + bw - pw, by - 16.0), pct,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, DIM)
	if detail != "":
		draw_string(font, Vector2(bx, by + 26.0), detail,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
