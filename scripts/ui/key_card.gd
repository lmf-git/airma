class_name KeyCard
extends Control
## The key card, on a canvas of its own.
##
## It is a page of static text -- eighty-odd strings laid out and measured --
## and it was drawn again on every frame of the game. Measured, 0.68 ms of a
## 14 ms frame for a picture that changes only when you climb into something
## else or press F2. A control of its own draws it once and is told to redraw
## only when the list it shows has actually changed.

var font: Font
var groups: Array = []

func show_keys(g: Array) -> void:
	groups = g
	queue_redraw()

## How wide a column is, and where the panel has to stop: the corner panels
## (minimap, radar) sit over the bottom of the screen, and a long card ran down
## behind them.
const COL_W := 520.0
const KEEP_CLEAR := 330.0

func _draw() -> void:
	if font == null or groups.is_empty():
		return
	var top := 118.0
	var bottom: float = maxf(get_viewport_rect().size.y - KEEP_CLEAR, top + 200.0)
	# Lay the rows out first, down one column and on into the next when it
	# would run past the bottom: a heading starts a column only with at least
	# two of its rows under it.
	var items: Array = []        # [column, y, kind, a, b]
	var col := 0
	var y := top
	var deepest := top
	for g in groups:
		if y + 22.0 + 2.0 * 19.0 > bottom and y > top:
			col += 1
			y = top
		items.append([col, y, 0, str(g[0]), ""])
		y += 22.0
		for row in g[1]:
			if y > bottom:
				col += 1
				y = top
			items.append([col, y, 1, str(row[0]), str(row[1])])
			y += 19.0
			deepest = maxf(deepest, y)
		y += 4.0
	var x0 := 26.0
	var box := Rect2(x0 - 14, top - 30, COL_W * float(col + 1) - 10.0, deepest - top + 24)
	draw_rect(box, Color(0.02, 0.04, 0.06, 0.55), true)
	draw_rect(box, Color(0.4, 0.9, 0.6, 0.35), false, 1.0)
	for it in items:
		var x: float = x0 + COL_W * float(it[0])
		if int(it[2]) == 0:
			draw_string(font, Vector2(x, it[1]), it[3],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.45, 0.95, 0.65))
		else:
			draw_string(font, Vector2(x + 6, it[1]), it[3],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 0.95, 0.7))
			draw_string(font, Vector2(x + 116, it[1]), it[4],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.82, 0.9, 0.95))
