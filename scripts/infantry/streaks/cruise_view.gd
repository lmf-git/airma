class_name CruiseView
extends Control
## What is drawn over the view from the nose: the aiming mark, the height, and
## a box on everything of theirs that can be seen from up there.

var missile: CruiseMissile = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_d: float) -> void:
	queue_redraw()

func _mark(cam: Camera3D, at: Vector3, half: float, col: Color, tag: String) -> void:
	if cam.is_position_behind(at):
		return
	var p: Vector2 = cam.unproject_position(at)
	var d: float = cam.global_position.distance_to(at)
	var px: float = clampf(half / maxf(d, 1.0) * size.y * 0.9, 7.0, 60.0)
	draw_rect(Rect2(p - Vector2(px, px), Vector2(px, px) * 2.0), col, false, 2.0)
	if tag != "":
		draw_string(ThemeDB.fallback_font, p + Vector2(px + 4.0, 4.0), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

func _draw() -> void:
	if not is_instance_valid(missile) or not is_instance_valid(missile.arena):
		return
	var cam: Camera3D = missile._cam
	if not cam.current:
		return
	var mid := size * 0.5
	var w := Color(1, 1, 1, 0.9)
	for a in 4:
		var u := Vector2.RIGHT.rotated(a * PI * 0.5)
		draw_line(mid + u * 14.0, mid + u * 44.0, w, 2.0)
	draw_arc(mid, 3.0, 0.0, TAU, 12, w, 2.0)
	var arena: CqbMatch = missile.arena
	var red := Color(1.0, 0.25, 0.2)
	for s in arena.soldiers:
		if is_instance_valid(s) and (s as Soldier).team != 0 and (s as Soldier).is_alive():
			_mark(cam, (s as Node3D).global_position + Vector3(0, 1.0, 0), 1.6, red, "")
	var amber := Color(1.0, 0.7, 0.2)
	for v in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(v) or not (v is Node3D) or v is Soldier or v is Walker \
				or not ("team" in v) or int(v.team) == 0:
			continue
		if v.has_method("is_alive") and not v.is_alive():
			continue
		_mark(cam, (v as Node3D).global_position + Vector3(0, 1.5, 0), 5.0, amber,
			String(v.call("display_name")) if v.has_method("display_name") else "VEHICLE")
	# the mark it was sent at
	_mark(cam, missile.target, 3.0, Color(1, 1, 1, 0.6), "MARK")
	var gy: float = Sim.height_at(missile.global_position.x, missile.global_position.z)
	draw_string(ThemeDB.fallback_font, Vector2(28, size.y - 60),
		"CRUISE MISSILE    ALT %d m    %d km/h    mouse or W/S/A/D aims it" % [
			int(missile.global_position.y - gy), int(missile.vel.length() * 3.6)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, w)
