class_name CqbMap
extends Control
## Him in the middle, north up, the buildings round him drawn from the
## buildings themselves, and everyone he is entitled to know about.
##
## It was the arena's own survey picture: a fixed square two hundred and sixty
## metres across, drawn the same whatever he did. Walk out of the arena and he
## walked off the map; stand at one end of it and half the map was what was
## behind him. Now it goes where he goes. The arena's edge is drawn on it, so
## where the fight is still reads.
##
## Its own control, so that it is clipped to its own box, and the buildings
## are one mesh rebuilt only when he has moved or the town has changed: a few
## hundred footprints filled one by one every frame was a few hundred polygon
## triangulations a frame.

const SPAN := 300.0               # metres across the box
const BLUE := Color(0.35, 0.72, 1.0)
const RED := Color(1.0, 0.2, 0.15)
var state: Dictionary = {}
var fed_at := -10
var _mesh: ArrayMesh = null
var _mesh_at := Vector2(INF, INF)
var _mesh_t := 0.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func feed(cs: Dictionary, box: Rect2) -> void:
	state = cs
	fed_at = Engine.get_process_frames()
	position = box.position
	size = box.size
	queue_redraw()

func _process(delta: float) -> void:
	_mesh_t -= delta
	# not fed this frame: he is not on foot in a street fight any more
	if Engine.get_process_frames() - fed_at > 2 and not state.is_empty():
		state = {}
		queue_redraw()

## Every footprint within reach, as triangles in metres from where he was.
## Rebuilt every couple of seconds as well, because buildings come down.
func _rebuild(me: Vector2) -> void:
	_mesh_at = me
	_mesh_t = 2.0
	_mesh = null
	var reach: float = SPAN * 0.75 + 30.0
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	for f in Obstacles.footprints(me - Vector2(reach, reach), me + Vector2(reach, reach), 3000):
		var fh: Vector2 = f[1]
		if minf(fh.x, fh.y) < 0.15:
			continue
		var fc: Vector2 = (f[0] as Vector2) - me
		var fy: float = f[2]
		var ax := Vector2(cos(fy), -sin(fy)) * fh.x
		var az := Vector2(sin(fy), cos(fy)) * fh.y
		var col := Color(0.62, 0.68, 0.74, 0.88) if float(f[3]) > 4.0 \
			else Color(0.52, 0.47, 0.38, 0.88)
		var p0: Vector2 = fc - ax - az
		var p1: Vector2 = fc + ax - az
		var p2: Vector2 = fc + ax + az
		var p3: Vector2 = fc - ax + az
		verts.append_array(PackedVector2Array([p0, p1, p2, p0, p2, p3]))
		for k in 6:
			cols.append(col)
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

func _draw() -> void:
	if state.is_empty():
		return
	var me: Vector2 = state.get("me_w", Vector2.ZERO)
	var ppm: float = size.x / SPAN
	var mid: Vector2 = size * 0.5
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, Color(0.03, 0.06, 0.09, 0.62))
	if _mesh == null or _mesh_at.distance_to(me) > 12.0 or _mesh_t <= 0.0:
		_rebuild(me)
	if _mesh != null:
		draw_set_transform(mid + (_mesh_at - me) * ppm, 0.0, Vector2(ppm, ppm))
		draw_mesh(_mesh, null)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# where the fight is
	var area: Rect2 = state.get("area", Rect2())
	if area.size.x > 0.0:
		draw_rect(Rect2(mid + (area.position - me) * ppm, area.size * ppm),
			Color(1.0, 0.8, 0.3, 0.5), false, 1.2)
	if float(state.get("uav", 0.0)) > 0.0:
		# the sweep, so it is obvious why there is red on the map
		var sw: float = fmod(Time.get_ticks_msec() * 0.001, 2.0) / 2.0
		draw_line(Vector2(size.x * sw, 0.0), Vector2(size.x * sw, size.y),
			Color(1, 0.3, 0.2, 0.35), 2.0)
	# their counter-UAV: the picture is noise and nobody is on it
	if float(state.get("jammed", 0.0)) > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(float(Time.get_ticks_msec()) / 80.0)
		for _i in 260:
			var q := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			draw_rect(Rect2(q, Vector2(3, 2)), Color(0.8, 0.85, 0.8, rng.randf_range(0.15, 0.6)))
		draw_string(ThemeDB.fallback_font, Vector2(8, 16), "JAMMED",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(1.0, 0.4, 0.3))
	else:
		for d in state.get("dots_w", []):
			var p: Vector2 = mid + ((d[0] as Vector2) - me) * ppm
			if frame.has_point(p):
				draw_circle(p, 3.2, BLUE if int(d[1]) == 0 else RED)
	var yaw: float = state.get("yaw", 0.0)
	var fw := Vector2(-sin(yaw), -cos(yaw))
	var rt := Vector2(-fw.y, fw.x)
	draw_colored_polygon(PackedVector2Array([mid + fw * 8.0, mid - fw * 5.0 + rt * 5.0,
		mid - fw * 2.0, mid - fw * 5.0 - rt * 5.0]), Color(1, 1, 1))
	draw_rect(frame, Color(0.6, 0.75, 0.9, 0.7), false, 1.2)
	# a scale, because nothing else on it says how far anything is
	var bar: float = 50.0 * ppm
	draw_line(Vector2(6, size.y - 8), Vector2(6 + bar, size.y - 8), Color(1, 1, 1, 0.8), 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(8 + bar, size.y - 4), "50 m",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
