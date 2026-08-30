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

const ACCENT := Color(0.62, 0.92, 1.0)
const DIM := Color(0.42, 0.55, 0.68)
const BAR_BACK := Color(0.10, 0.16, 0.22)
## Sky, top to bottom: night at the zenith through to the last of the light
## sitting on the horizon.
const SKY_TOP := Color(0.020, 0.035, 0.062)
const SKY_MID := Color(0.047, 0.085, 0.130)
const SKY_LOW := Color(0.115, 0.170, 0.215)
const GLOW := Color(0.30, 0.46, 0.56)
## Two ridge lines and the ground, each darker than the one behind it, which is
## what gives a flat drawing any depth at all.
const RIDGE_FAR := Color(0.055, 0.086, 0.115)
const RIDGE_NEAR := Color(0.030, 0.048, 0.066)
const GROUND := Color(0.016, 0.026, 0.036)

## A ridge line across the screen, built from a few sine waves at different
## rates so it never repeats within the width.
func _ridge(vs: Vector2, base: float, amp: float, phase_off: float,
		col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 64
	for i in steps + 1:
		var u: float = float(i) / float(steps)
		var x: float = u * vs.x
		var h: float = sin(u * 6.1 + phase_off) * 0.55 + sin(u * 13.7 + phase_off * 2.3) * 0.30 \
			+ sin(u * 27.3 + phase_off * 4.1) * 0.15
		pts.append(Vector2(x, base - h * amp))
	pts.append(Vector2(vs.x, vs.y))
	pts.append(Vector2(0.0, vs.y))
	draw_colored_polygon(pts, col)


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
	# The viewport's size, not this Control's.
	#
	# It is anchored to the full rect, but nothing lays it out before it first
	# draws -- measured, `size` is still (0, 0) on the first frames -- so every
	# rectangle came out zero-sized and the screen was whatever colour the
	# viewport clears to. Asking the viewport is immune to when layout happens.
	var vs := get_viewport_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return
	var hy: float = vs.y * 0.62
	# --- sky ------------------------------------------------------------
	# Banded rather than one flat fill: a gradient is most of the difference
	# between a backdrop and a painted rectangle.
	var bands := 48
	for i in bands:
		var u: float = float(i) / float(bands - 1)
		var c: Color = SKY_TOP.lerp(SKY_MID, clampf(u * 1.6, 0.0, 1.0))
		if u > 0.55:
			c = c.lerp(SKY_LOW, (u - 0.55) / 0.45)
		draw_rect(Rect2(0.0, hy * u, vs.x, hy / float(bands - 1) + 1.0), c)
	# stars, thinning out towards the horizon
	for i in 90:
		var sx: float = fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var sy: float = fmod(sin(float(i) * 78.233) * 24634.6345, 1.0)
		sx = absf(sx)
		sy = absf(sy)
		var y: float = sy * sy * hy * 0.92
		var fade: float = 1.0 - y / hy
		var tw: float = 0.55 + 0.45 * sin(_t * 1.7 + float(i) * 2.1)
		draw_rect(Rect2(sx * vs.x, y, 1.6, 1.6),
			Color(0.75, 0.85, 0.95, 0.30 * fade * fade * tw))
	# the last of the light along the horizon
	for i in 22:
		var u2: float = float(i) / 21.0
		draw_rect(Rect2(0.0, hy - (1.0 - u2) * hy * 0.16,
			vs.x, hy * 0.16 / 21.0 + 1.0),
			Color(GLOW.r, GLOW.g, GLOW.b, 0.10 * u2 * u2))
	# --- country --------------------------------------------------------
	_ridge(vs, hy + 2.0, vs.y * 0.055, 0.7, RIDGE_FAR)
	_ridge(vs, hy + vs.y * 0.045, vs.y * 0.038, 3.1, RIDGE_NEAR)
	draw_rect(Rect2(0.0, hy + vs.y * 0.11, vs.x, vs.y), GROUND)
	# --- title ----------------------------------------------------------
	var font := ThemeDB.fallback_font
	var cx: float = vs.x * 0.5
	var title := "COMBINED ARMS"
	# Letter-spaced by hand: drawn as one string it is just a word, and spacing
	# it out is what makes a title read as a title.
	var tsz := 46
	var gap := 7.0
	var tw2 := 0.0
	for ch in title:
		tw2 += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x + gap
	tw2 -= gap
	var tx: float = cx - tw2 * 0.5
	var ty: float = hy - vs.y * 0.16
	for ch2 in title:
		draw_string(font, Vector2(tx, ty), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1,
			tsz, Color(0.90, 0.96, 1.0))
		tx += font.get_string_size(ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x + gap
	# a rule under it, fading out at both ends
	var rw: float = tw2 * 0.62
	for i in 40:
		var u3: float = float(i) / 39.0
		var a: float = (1.0 - absf(u3 - 0.5) * 2.0)
		draw_rect(Rect2(cx - rw * 0.5 + rw * u3, ty + 14.0, rw / 40.0 + 1.0, 1.0),
			Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45 * a))
	# --- progress -------------------------------------------------------
	var bw: float = minf(vs.x * 0.52, 620.0)
	var bx: float = cx - bw * 0.5
	var by: float = hy + vs.y * 0.17
	# tick marks behind the bar, so the travel has a scale to be read against
	for i in 11:
		var txp: float = bx + bw * float(i) / 10.0
		draw_rect(Rect2(txp, by - 7.0, 1.0, 4.0),
			Color(DIM.r, DIM.g, DIM.b, 0.35))
	draw_rect(Rect2(bx, by, bw, 6.0), BAR_BACK)
	draw_rect(Rect2(bx, by, bw * _shown, 6.0), ACCENT)
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
	# --- vignette -------------------------------------------------------
	# Four fading bands rather than a texture: it only has to take the hard
	# edge off the frame.
	var vg := vs.y * 0.16
	for i in 16:
		var u4: float = float(i) / 15.0
		var a2: float = 0.16 * (1.0 - u4) * (1.0 - u4)
		var th: float = vg / 16.0 + 1.0
		draw_rect(Rect2(0.0, u4 * vg - th, vs.x, th), Color(0, 0, 0, a2))
		draw_rect(Rect2(0.0, vs.y - u4 * vg, vs.x, th), Color(0, 0, 0, a2))
