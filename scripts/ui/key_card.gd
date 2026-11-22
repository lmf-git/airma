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
