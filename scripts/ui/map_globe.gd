class_name MapGlobe
extends RefCounted
## The map as the planet rather than as a chart of one cap of it: the turning globe, its body and its sharper patch under the view, the graticule, and everything marked on it. Split out of `map_view.gd`; the map has one as `globe_view`.

var mv: MapView

var _patch_tex: ImageTexture = null

## The window the texture we are holding covers: u0, u1, v0, v1.
var _patch_win := PackedFloat32Array()

## The window a bake is in flight for, empty when nothing is being baked.
var _patch_asked := PackedFloat32Array()

## And the window wanted since that one went out, empty when there is none.
##
## Two of these, not one. The view asks for a window every frame it moves and
## only one bake runs at a time, so while a drag is under way there is a window
## being drawn and a newer one waiting -- and they were the same variable. The
## picture that came back was of the window that had been asked for, and it was
## hung on the window asked for *since*: the detailed cap landed somewhere it
## was not a picture of and slid about the globe as you zoomed.
var _patch_next := PackedFloat32Array()

var _patch_t0 := 0

var _patch_ms := 0.0

func _init(owner_node: MapView) -> void:
	mv = owner_node

## Open the map on the planet.
##
## This used to switch between two maps. There is one now: everything the flat
## chart drew is drawn on the planet -- the aerodromes, the towns, the
## objectives, the carrier, the contacts, the other players, the fire missions
## and their warhead marks -- and the roads are inked into the sheet it is
## painted with. Two pictures of one world, drawn by two sets of code, is how
## they came to disagree about where things were in the first place.
##
## The flat chart survives only for `--flat`, the legacy square world, which has
## no planet to draw.
func toggle_globe() -> void:
	if not mv.visible:
		mv.toggle()
	mv.queue_redraw()

## Unit direction from the planet centre for a point on the ground, given where
## it is on the flat chart. The world's horizontal coordinates *are* the offsets
## from the axis, so this is the sphere point at that offset and nothing has to
## be unprojected.
func _globe_dir(w: Vector2) -> Vector3:
	# The chart's own projection, which is the one the ground is generated
	# against. This read
	#
	#     Vector3(w.x, sqrt(R*R - w.length_squared()), w.y).normalized()
	#
	# -- an orthographic inverse about `Vector3.UP`, from when the chart was
	# always at `UP` and the two agreed near the origin. The chart is now put on
	# whichever country the sortie is flown from, so this had every mark on the
	# planet map -- contacts, satellites, your own aeroplane -- projected as
	# though the world were somewhere it is not, about eleven hundred kilometres
	# out. The globe's own mesh is indexed from the chart; the things drawn over
	# it have to be as well.
	return Sim.chart_to_dir(w.x, w.y)

func _globe_basis() -> Basis:
	# Bring the chart's origin round to face the viewer, then let drag turn it
	# away from there.
	#
	# This used to rotate the planet's own up into view -- "the pole, the
	# chart's origin", which were the same direction for as long as the chart
	# was always at `Vector3.UP`. They are different things now: the chart is
	# put on whichever country the sortie is flown from, so opening the planet
	# map looked at a fixed point of the globe rather than at where you are.
	# Built from the chart's own frame, north is up on screen and east is
	# right, which is what a map is.
	var frame := Basis(Sim.chart_east, -Sim.chart_south,
		Sim.chart_origin).transposed()
	return Basis(Vector3.RIGHT, mv.globe_tilt) * Basis(Vector3.UP, mv.globe_spin) \
		* frame

## Screen position of a ground point, and whether it is on the near side. z > 0
## faces the viewer; anything else is round the back and must not be drawn.
func _globe_at(w: Vector2, org: Vector2, rad: float, b: Basis, lift := 1.0) -> Vector3:
	var v: Vector3 = b * _globe_dir(w)
	return Vector3(org.x + v.x * rad * lift, org.y - v.y * rad * lift, v.z)

## Where the sun is, in the same view frame, so the ball is lit the way the
## world is and the terminator falls where night does.
func _globe_light(b: Basis) -> Vector3:
	# The sun as a direction from the PLANET'S centre, which is the frame the
	# globe's own normals are in.
	#
	# `solar_angles` gives elevation and azimuth in the local horizon frame at
	# the chart's origin, and this used to hand that straight to the shading.
	# The two were the same thing while the chart sat on the planet's pole; they
	# are not now the chart is put on whichever country the sortie is flown
	# from. At 42 degrees south the globe was lit from a direction rotated by
	# that much -- measured, the disc came out brighter at midnight (0.122) than
	# at noon (0.083), which is the terminator drawn on the wrong side.
	#
	# Taken from the world's own light rather than worked out again: the world
	# frame *is* the local horizon frame at the chart's origin, so the light's
	# `basis.z` -- the direction toward the sun -- decomposes into up, east and
	# north there, and those three axes are known on the planet. No second
	# derivation, and no azimuth convention to get backwards.
	var w := Vector3(0.0, 0.9, -0.44)
	if mv.world != null and is_instance_valid(mv.world):
		var sun: Variant = mv.world.get("_sun")
		if sun != null and is_instance_valid(sun) and sun is Node3D:
			w = (sun as Node3D).global_transform.basis.z
	if not Sim.globe:
		return (b * w).normalized()
	# up is +Y in the world frame, east is +X and north is -Z.
	var d: Vector3 = (Sim.chart_origin * w.y
		+ Sim.chart_east * w.x
		+ (-Sim.chart_south) * (-w.z)).normalized()
	return (b * d).normalized()

func _draw_globe() -> void:
	var vp := mv.get_viewport_rect().size
	mv.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.01, 0.015, 0.025, 0.96), true)
	var org := vp * 0.5
	var rad: float = minf(vp.x, vp.y) * 0.42 * mv.globe_zoom
	var b := _globe_basis()
	# Round the moon, the moon is the middle of the map. The planet stays where
	# it is in space -- sixty of its own radii off to one side -- and what is
	# on the screen is the thing being flown round.
	var crew: LaunchVehicle = mv._crewed_rocket()
	if crew != null and crew.by_moon():
		var fv: Vector3 = b * (Sim.moon_dir() * Sim.MOON_DIST / Sim.PLANET_R)
		org -= Vector2(fv.x, -fv.y) * rad
	var lit := _globe_light(b)
	_globe_body(org, rad, b, lit)
	_globe_patch(org, rad, b, lit)
	_globe_graticule(org, rad, b)
	_globe_marks(org, rad, b)
	mv._globe_space(org, rad, b)
	# Whatever you are in, not the aeroplane: on a ship's bridge or in a tank
	# the readout was the parked aircraft's, or nothing.
	var me2: Node3D = mv._me()
	var alt := 0.0
	var lat := 0.0
	if me2 != null:
		var ap: Vector3 = me2.global_position
		alt = Sim.altitude(ap)
		lat = Sim.latitude_at(ap.x, ap.z)
	mv._label(Vector2(18, 26), "PLANET  —  drag to turn, wheel to zoom (in over the theatre for the street map), "
		+ "right click to lay a fire mission, shift+click for an objective", Color(0.75, 0.85, 1.0), 15)
	mv._label(Vector2(18, 48), "globe %.0f km across; you are %.1f km up at %.2f%s" % [
		Sim.PLANET_R * 2.0 * 0.001, alt * 0.001,
		absf(rad_to_deg(lat)), "N" if lat >= 0.0 else "S"],
		Color(0.6, 0.68, 0.78), 13)
	# The same position line the chart carries, so switching between the two
	# does not lose it.
	if me2 != null:
		var mp: Vector3 = me2.global_position
		mv._label(Vector2(24, vp.y - 96), "POS  %+.1f km E   %+.1f km N   ALT %d ft" % [
			mp.x * 0.001, -mp.z * 0.001, int(alt * 3.28084)],
			Color(0.7, 1.0, 0.8))

## The ball itself: ocean, shaded by the real sun. Emitted as one triangle array
## rather than a few thousand polygons, because it is redrawn every frame.
func _globe_body(org: Vector2, rad: float, b: Basis, lit: Vector3) -> void:
	# The generated planet: the globe reads the same equirectangular sheet the
	# orbital body does, so the map and the view out of the window are the same
	# world.
	#
	# The mesh is built in the extension. Written here it was four and a half
	# thousand quads -- eighteen thousand corners, each a little trigonometry
	# and a basis multiply -- rebuilt every frame the map is open, and the map
	# redraws every frame.
	var sheet: Texture2D = mv._planet_sheet()
	if sheet == null or Sim.native == null:
		return
	mv.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var mesh: Array = Sim.native.globe_mesh(MapView.GLOBE_RINGS, MapView.GLOBE_SEGS, org, rad,
		b, lit)
	_submit(mesh, sheet.get_rid())

## Hand a built mesh to the canvas.
func _submit(mesh: Array, tex: RID) -> void:
	if mesh.size() != 4:
		return
	var idx: PackedInt32Array = mesh[3]
	if idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
		mv.get_canvas_item(), idx, mesh[0] as PackedVector2Array,
		mesh[2] as PackedColorArray, mesh[1] as PackedVector2Array,
		PackedInt32Array(), PackedFloat32Array(), tex)

## The part of the planet that is on screen, in sheet coordinates.
##
## Empty when the whole ball fits, because then the base sheet is already as
## much detail as the screen can show.
func _globe_window(rad: float, b: Basis) -> PackedFloat32Array:
	var vp := mv.get_viewport_rect().size
	var half: float = minf(vp.x, vp.y) * 0.5
	if rad <= half * 1.25:
		return PackedFloat32Array()
	# The cap that reaches the corners of the screen, with a margin so a small
	# drag does not run off the edge of what has been baked.
	var ang: float = asin(clampf(half * 1.45 * sqrt(2.0) / rad, 0.0, 1.0))
	# Snapped, as the satellite view's is (`Planet._window_at`), so a view
	# come back to asks for a window already on disk.
	ang = 0.01 * pow(1.5, ceilf(log(maxf(ang, 0.01) / 0.01) / log(1.5) - 1e-4))
	var pole: Vector3 = Sim.PLANET_NORTH
	var home := Vector3.UP
	var east: Vector3 = pole.cross(home).normalized()
	# Whichever way the globe has been turned, this is the point under the
	# middle of the screen.
	var c: Vector3 = (b.inverse() * Vector3(0.0, 0.0, 1.0)).normalized()
	var uvc: Vector2 = mv._globe_uv(c, pole, home, east)
	var dv: float = ang / PI
	uvc.y = snappedf(uvc.y, dv * 0.25)
	var v0: float = uvc.y - dv
	var v1: float = uvc.y + dv
	# Meridians converge, so a cap of a given angle spans more longitude the
	# nearer the pole it is. Over the pole itself it spans all of them.
	var lat: float = (0.5 - uvc.y) * PI
	var span: float = cos(absf(lat)) 
	var du: float = 0.5 if v0 <= 0.0 or v1 >= 1.0 or span < 0.02 \
		else minf(ang / TAU / span, 0.5)
	if du < 0.5:
		uvc.x = snappedf(uvc.x, du * 0.25)
	return PackedFloat32Array([uvc.x - du, uvc.x + du,
		clampf(v0, 0.0, 1.0), clampf(v1, 0.0, 1.0)])

## Bake the window if what we are holding no longer covers it.
##
## Asked for, not waited on. The bake is half a million texels of the full
## height field -- forty milliseconds -- and done in line that is a hitch every
## time the map is zoomed or dragged. The extension bakes it on a thread of its
## own and this collects it when it is ready; until then the globe keeps
## drawing the patch it already has, or the base sheet if there is none yet.
func _want_patch(win: PackedFloat32Array) -> void:
	if Sim.native == null:
		return
	_collect_patch()
	if _patch_win.size() == 4:
		var wu: float = _patch_win[1] - _patch_win[0]
		var wv: float = _patch_win[3] - _patch_win[2]
		var nu: float = win[1] - win[0]
		var nv: float = win[3] - win[2]
		# Still good if it has not moved much and the zoom has not changed
		# enough to want a different scale.
		if absf(nu - wu) < wu * MapView.PATCH_SLACK and absf(nv - wv) < wv * MapView.PATCH_SLACK \
				and absf(win[0] - _patch_win[0]) < wu * MapView.PATCH_SLACK \
				and absf(win[2] - _patch_win[2]) < wv * MapView.PATCH_SLACK:
			return
	# One in flight at a time, and it is the newest window that is wanted: if
	# the view is still moving, what goes out next is whatever was being asked
	# for when the one in flight finished.
	if _patch_asked.size() == 4:
		_patch_next = win.duplicate()
		return
	_patch_t0 = Time.get_ticks_usec()
	# Kept on disk: a small picture, read back in line.
	var path := _cache_path(win)
	if FileAccess.file_exists(path):
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f != null:
			var n: int = f.get_32()
			var got := f.get_buffer(n)
			f.close()
			if _apply_patch(got, win):
				mv.queue_redraw()
				return
	if Sim.native.patch_request(MapView.PATCH_RES, MapView.PATCH_RES, Sim.PLANET_NORTH,
			win[0], win[1], win[2], win[3]):
		_patch_asked = win.duplicate()
		_patch_next = PackedFloat32Array()

const CACHE := "user://map_patch_cache"

func _cache_path(win: PackedFloat32Array) -> String:
	if Planet._code_sig == "":
		Planet._code_sig = WorldBake.signature()
	var key := "map|%s|%d|%.5f,%.5f,%.5f,%.5f|%d" % [Planet._code_sig, MapView.PATCH_RES,
		win[0], win[1], win[2], win[3], int(round(Sim.season * 10.0))]
	return "%s/%s.bin" % [CACHE, key.sha256_text().substr(0, 24)]

func _apply_patch(buf: PackedByteArray, win: PackedFloat32Array) -> bool:
	if buf.size() < MapView.PATCH_RES * MapView.PATCH_RES * 3:
		return false
	var img := Image.create_from_data(MapView.PATCH_RES, MapView.PATCH_RES, false,
		Image.FORMAT_RGB8, buf.slice(0, MapView.PATCH_RES * MapView.PATCH_RES * 3))
	_patch_tex = ImageTexture.create_from_image(img)
	_patch_win = win.duplicate()
	return true

## Take delivery of a finished bake.
func _collect_patch() -> void:
	if _patch_asked.size() != 4 or not Sim.native.patch_ready():
		return
	var buf: PackedByteArray = Sim.native.patch_take()
	# The window this picture is *of*, which is the one that went out with
	# the request and not whatever the view has moved on to since.
	if _apply_patch(buf, _patch_asked):
		_patch_ms = float(Time.get_ticks_usec() - _patch_t0) * 0.001
		var path := _cache_path(_patch_asked)
		var keep := buf.slice(0, MapView.PATCH_RES * MapView.PATCH_RES * 3)
		WorkerThreadPool.add_task(func() -> void:
			DirAccess.make_dir_recursive_absolute(CACHE)
			var w := FileAccess.open_compressed(path + ".part", FileAccess.WRITE,
				FileAccess.COMPRESSION_ZSTD)
			if w != null:
				w.store_32(keep.size())
				w.store_buffer(keep)
				w.close()
				DirAccess.rename_absolute(path + ".part", path), false, "map patch save")
	_patch_asked = PackedFloat32Array()
	# Whatever was wanted while that one was running goes out now.
	if _patch_next.size() == 4:
		var again := _patch_next
		_patch_next = PackedFloat32Array()
		_want_patch(again)
	mv.queue_redraw()

## The detailed cap, drawn over the base globe.
func _globe_patch(org: Vector2, rad: float, b: Basis, lit: Vector3) -> void:
	var win := _globe_window(rad, b)
	if win.is_empty():
		return
	_want_patch(win)
	if _patch_tex == null or _patch_win.size() != 4:
		return
	var w := _patch_win
	var mesh: Array = Sim.native.globe_patch_mesh(MapView.PATCH_GRID,
		w[0], w[1], w[2], w[3], org, rad, b, lit)
	_submit(mesh, _patch_tex.get_rid())

## The inverse of `_globe_uv`: where a point of the sheet lies on the planet.
func _uv_dir(u: float, v: float, pole: Vector3, home: Vector3,
		east: Vector3) -> Vector3:
	var lat: float = (0.5 - v) * PI
	var lon: float = (u - 0.5) * TAU
	return (pole * sin(lat)
		+ (home * cos(lon) + east * sin(lon)) * cos(lat)).normalized()

func _globe_graticule(org: Vector2, rad: float, b: Basis) -> void:
	var col := Color(0.42, 0.55, 0.68, 0.35)
	# The frame the graticule is drawn in: the planet's north, and any two axes
	# across it. `u` is where a meridian starts, which is arbitrary -- what is
	# not arbitrary is that it is perpendicular to the pole.
	var pole: Vector3 = Sim.PLANET_NORTH
	var u0: Vector3 = Vector3.UP.cross(pole).normalized()
	if u0.length() < 0.5:
		u0 = Vector3.RIGHT.cross(pole).normalized()
	var v0: Vector3 = pole.cross(u0).normalized()
	for ring in range(1, 12):
		var th: float = PI * float(ring) / 12.0
		var run := PackedVector2Array()
		# The equator is the one worth seeing, so it is drawn heavier below.
		for j in range(MapView.GLOBE_SEGS + 1):
			var ph: float = TAU * float(j) / float(MapView.GLOBE_SEGS)
			var n: Vector3 = pole * cos(th) \
				+ (u0 * cos(ph) + v0 * sin(ph)) * sin(th)
			var v: Vector3 = b * n
			if v.z <= 0.0:
				if run.size() > 1:
					mv.draw_polyline(run, col, 1.0)
				run = PackedVector2Array()
				continue
			run.append(Vector2(org.x + v.x * rad, org.y - v.y * rad))
		if run.size() > 1:
			mv.draw_polyline(run, col, 1.0)
	# the equator, heavier, because it is the line the airfield sits on
	var eq := PackedVector2Array()
	for j2 in range(MapView.GLOBE_SEGS + 1):
		var ph3: float = TAU * float(j2) / float(MapView.GLOBE_SEGS)
		var n3: Vector3 = u0 * cos(ph3) + v0 * sin(ph3)
		var v3: Vector3 = b * n3
		if v3.z <= 0.0:
			if eq.size() > 1:
				mv.draw_polyline(eq, Color(0.62, 0.78, 0.92, 0.55), 1.6)
			eq = PackedVector2Array()
			continue
		eq.append(Vector2(org.x + v3.x * rad, org.y - v3.y * rad))
	if eq.size() > 1:
		mv.draw_polyline(eq, Color(0.62, 0.78, 0.92, 0.55), 1.6)
	for mer in range(12):
		var ph2: float = TAU * float(mer) / 12.0
		var run2 := PackedVector2Array()
		for i in range(MapView.GLOBE_RINGS + 1):
			var th2: float = PI * float(i) / float(MapView.GLOBE_RINGS)
			var n2: Vector3 = pole * cos(th2) \
				+ (u0 * cos(ph2) + v0 * sin(ph2)) * sin(th2)
			var v2: Vector3 = b * n2
			if v2.z <= 0.0:
				if run2.size() > 1:
					mv.draw_polyline(run2, col, 1.0)
				run2 = PackedVector2Array()
				continue
			run2.append(Vector2(org.x + v2.x * rad, org.y - v2.y * rad))
		if run2.size() > 1:
			mv.draw_polyline(run2, col, 1.0)

## Everything that is not the ground: where the world's works are, where you are,
## is on the map, and what is in orbit.
func _globe_marks(org: Vector2, rad: float, b: Basis) -> void:
	# the mapped square, so the ground under the chart can be picked out
	var edge := PackedVector2Array()
	var steps := 20
	for k in range(steps * 4 + 1):
		var t: float = float(k % (steps * 4)) / float(steps)
		var w := Vector2.ZERO
		if t < 1.0:
			w = Vector2(lerpf(-MapView.HALF, MapView.HALF, t), -MapView.HALF)
		elif t < 2.0:
			w = Vector2(MapView.HALF, lerpf(-MapView.HALF, MapView.HALF, t - 1.0))
		elif t < 3.0:
			w = Vector2(lerpf(MapView.HALF, -MapView.HALF, t - 2.0), MapView.HALF)
		else:
			w = Vector2(-MapView.HALF, lerpf(MapView.HALF, -MapView.HALF, t - 3.0))
		var p := _globe_at(w, org, rad, b)
		if p.z > 0.0:
			edge.append(Vector2(p.x, p.y))
		elif edge.size() > 1:
			mv.draw_polyline(edge, Color(0.55, 0.75, 0.95, 0.6), 1.4)
			edge = PackedVector2Array()
	if edge.size() > 1:
		mv.draw_polyline(edge, Color(0.55, 0.75, 0.95, 0.6), 1.4)
	# the objective, the same mark the flat chart drew -- the globe drew none,
	# so one set from the pod or the satellite terminal was nowhere on the map
	if Sim.objective != Vector3.INF:
		var oq := _globe_at(Vector2(Sim.objective.x, Sim.objective.z), org, rad, b)
		if oq.z > 0.0:
			var op := Vector2(oq.x, oq.y)
			var oc := Color(1.0, 0.82, 0.25)
			mv.draw_arc(op, 9.0, 0.0, TAU, 20, oc, 2.0)
			mv.draw_line(op + Vector2(-14, 0), op + Vector2(14, 0), oc, 1.4)
			mv.draw_line(op + Vector2(0, -14), op + Vector2(0, 14), oc, 1.4)
			mv._label(op + Vector2(12, -12), "OBJECTIVE", oc, 12)
	# the airfield, which is the pole and the origin of everything else
	var home := _globe_at(Vector2.ZERO, org, rad, b)
	if home.z > 0.0:
		mv.draw_arc(Vector2(home.x, home.y), 5.0, 0, TAU, 12,
			Color(0.9, 0.95, 1.0, 0.9), 1.6)
	# contacts, lifted to whatever height they are actually at
	for c in mv._contacts:
		# Validity before typing, as on the chart: the list is on a timer and
		# assigning a freed instance to a typed variable is itself the error.
		var nv: Variant = c["n"]
		if not is_instance_valid(nv):
			continue
		var n: Node3D = nv
		var np: Vector3 = n.global_position
		var lift0: float = 1.0 + maxf(Sim.altitude(np), 0.0) / Sim.PLANET_R
		var p2 := _globe_at(Vector2(np.x, np.z), org, rad, b, lift0)
		if p2.z <= 0.0:
			continue
		var col := Color(0.42, 0.80, 1.0)
		if bool(c.get("neutral", false)):
			col = Color(0.85, 0.82, 0.45)
		elif bool(c["hostile"]):
			col = Color(1.0, 0.44, 0.36)
		var here0 := Vector2(p2.x, p2.y)
		if n is Aircraft:
			mv.draw_polyline(PackedVector2Array([here0 + Vector2(-4, 3),
				here0 + Vector2(0, -4), here0 + Vector2(4, 3)]), col, 1.4)
		else:
			mv.draw_rect(Rect2(here0 - Vector2(2.5, 2.5), Vector2(5, 5)), col, true)
	# The aerodromes, the towns, the objectives and everyone in the session.
	#
	# These were on the flat chart only, so switching to the planet lost half of
	# what a tactical map is for. The chart was the map for as long as the world
	# was a square of ground; the planet is the map now, and everything the
	# chart drew has to be on it.
	#
	# The roads are not here: the network is fifty thousand legs and the map
	# redraws every frame, so they are inked into the sheet when it is baked.
	for fd in Sim.fields:
		var f: Dictionary = fd
		var at: Vector2 = f["at"]
		var yaw: float = float(f["yaw"])
		var half: float = Sim.RUNWAY_LEN * 0.5
		var along := Vector2(-sin(yaw), cos(yaw)) * half
		var pa := _globe_at(at - along, org, rad, b)
		var pb := _globe_at(at + along, org, rad, b)
		if pa.z <= 0.0 or pb.z <= 0.0:
			continue
		var who := String(f.get("who", ""))
		var fcol := Color(0.95, 0.95, 0.95) if who == Sim.home_faction \
			else Color(0.85, 0.78, 0.62)
		mv.draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y), fcol, 2.0)
		mv._label(Vector2(pb.x, pb.y) + Vector2(6, -6),
			who.to_upper() if who != "" else "RWY", fcol, 12)
	var sc := Scenery.current
	if sc != null:
		for t in sc.sites:
			var c: Vector2 = t["c"]
			var p := _globe_at(c, org, rad, b)
			if p.z <= 0.0:
				continue
			var fac := Sim.region_faction(c.x, c.y)
			var col := Color(0.75, 0.72, 0.6, 0.7)
			if fac == "russia" or fac == "china":
				col = Color(0.95, 0.55, 0.45, 0.75)
			var here2 := Vector2(p.x, p.y)
			# Radius on the screen the same way the chart works it out: the
			# globe is `rad` px for the planet's radius.
			mv.draw_arc(here2, maxf(float(t["r"]) / Sim.PLANET_R * rad, 2.0),
				0, TAU, 18, col, 1.2)
			if rad > 900.0:
				mv._label(here2 + Vector2(5, -5), String(t["name"]),
					Color(col.r, col.g, col.b, 1.0), 12)
	for z in mv.get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		var zp: Vector3 = z.global_position
		var p := _globe_at(Vector2(zp.x, zp.z), org, rad, b)
		if p.z <= 0.0:
			continue
		var col := Color(0.8, 0.8, 0.82)
		if z.owner_team == 0:
			col = Color(0.35, 0.75, 1.0)
		elif z.owner_team == 1:
			col = Color(1.0, 0.35, 0.3)
		mv.draw_arc(Vector2(p.x, p.y),
			maxf(float(z.radius) / Sim.PLANET_R * rad, 6.0), 0, TAU, 28, col, 1.8)
		mv._label(Vector2(p.x, p.y) - Vector2(4, 8), str(z.label), col)
	# Whatever the weapon camera is riding, so a shot can be followed on the
	# map as well as over its shoulder. Lifted by its own altitude, because a
	# round in flight is the one contact that is mostly not on the ground.
	if mv.world != null and is_instance_valid(mv.world.get("cam")):
		# Held as a Variant until it has been checked. A camera that has just
		# finished riding a round still holds the reference for a frame, and
		# assigning a freed instance to a typed variable is an error in itself.
		var riding_v: Variant = (mv.world.cam as Node).get("weapon_cam")
		if riding_v != null and is_instance_valid(riding_v) and riding_v is Node3D:
			var riding: Node3D = riding_v
			mv._draw_salvo(riding, func(w: Vector3, air: bool) -> Vector3:
				var lift: float = 1.0 + maxf(Sim.altitude(w), 0.0) / Sim.PLANET_R \
					if air else 1.0
				return _globe_at(Vector2(w.x, w.z), org, rad, b, lift))
			var rp: Vector3 = riding.global_position
			var rl: float = 1.0 + maxf(Sim.altitude(rp), 0.0) / Sim.PLANET_R
			var p := _globe_at(Vector2(rp.x, rp.z), org, rad, b, rl)
			if p.z > 0.0:
				var rq := Vector2(p.x, p.y)
				var rc := Color(1.0, 0.85, 0.35)
				mv.draw_arc(rq, 9.0, 0.0, TAU, 18, rc, 1.8)
				mv.draw_line(rq - Vector2(13, 0), rq + Vector2(13, 0), rc, 1.2)
				mv.draw_line(rq - Vector2(0, 13), rq + Vector2(0, 13), rc, 1.2)
				# a tether to the ground under it, as the satellites have: a
				# round at forty kilometres is nowhere near what is beneath it
				var rfoot := _globe_at(Vector2(rp.x, rp.z), org, rad, b)
				mv.draw_line(rq, Vector2(rfoot.x, rfoot.y),
					Color(rc.r, rc.g, rc.b, 0.35), 1.0)
				var nm2 := "ROUND"
				if "wid" in riding:
					nm2 = String(WeaponSpec.get_spec(String(riding.wid))["short"])
				mv._label(rq + Vector2(14, -8), nm2, rc, 12)
	if mv.world and is_instance_valid(mv.world.get("carrier")):
		var cp: Vector3 = mv.world.carrier.global_position
		var p := _globe_at(Vector2(cp.x, cp.z), org, rad, b)
		if p.z > 0.0:
			mv.draw_rect(Rect2(Vector2(p.x, p.y) - Vector2(5, 5), Vector2(10, 10)),
				Color(0.6, 0.8, 1.0), false, 1.6)
			mv._label(Vector2(p.x, p.y) + Vector2(9, 4), "CVN",
				Color(0.6, 0.8, 1.0))
	if mv.world != null and mv.world.get("net") != null \
			and (mv.world.net as NetLink).active:
		for pl in (mv.world.net as NetLink).player_positions():
			var e: Dictionary = pl
			var at3: Vector3 = e["at"]
			if at3 == Vector3.INF:
				continue
			var lift3: float = 1.0 + maxf(Sim.altitude(at3), 0.0) / Sim.PLANET_R
			var p := _globe_at(Vector2(at3.x, at3.z), org, rad, b, lift3)
			if p.z <= 0.0:
				continue
			var q3 := Vector2(p.x, p.y)
			var col := Color(0.40, 0.82, 1.0) if int(e["team"]) == 0 \
				else Color(1.0, 0.44, 0.36)
			if bool(e["me"]):
				col = Color(0.55, 1.0, 0.72)
			if String(e["kind"]) == "air":
				mv.draw_polyline(PackedVector2Array([q3 + Vector2(-6, 5),
					q3 + Vector2(0, -6), q3 + Vector2(6, 5)]), col, 1.8)
			else:
				mv.draw_rect(Rect2(q3 - Vector2(4, 4), Vector2(8, 8)), col, false, 1.6)
			mv._label(q3 + Vector2(9, -7), String(e["name"]), col, 12)
	# The fire mission and the warhead marks. Right click lays them and this is
	# where they show; without them the planet map could not do the one thing
	# the chart could do that reading the ground cannot.
	if mv.strategic_mark != Vector3.INF:
		var sp3 := _globe_at(Vector2(mv.strategic_mark.x, mv.strategic_mark.z),
			org, rad, b)
		if sp3.z > 0.0:
			var sq := Vector2(sp3.x, sp3.y)
			var sc3 := Color(1.0, 0.45, 0.2)
			mv.draw_arc(sq, 9.0, 0.0, TAU, 20, sc3, 1.8)
			mv.draw_line(sq - Vector2(13, 0), sq + Vector2(13, 0), sc3, 1.4)
			mv.draw_line(sq - Vector2(0, 13), sq + Vector2(0, 13), sc3, 1.4)
	if mv.tank != null and is_instance_valid(mv.tank) and mv.tank.is_indirect():
		var tq3 := _globe_at(Vector2(mv.tank.global_position.x,
			mv.tank.global_position.z), org, rad, b)
		if tq3.z > 0.0:
			mv.draw_rect(Rect2(Vector2(tq3.x, tq3.y) - Vector2(4, 4),
				Vector2(8, 8)), Color(0.4, 1.0, 0.5), false, 2.0)
		if mv.tank.map_target != Vector3.INF:
			var mq := _globe_at(Vector2(mv.tank.map_target.x, mv.tank.map_target.z),
				org, rad, b)
			if mq.z > 0.0:
				var mp3 := Vector2(mq.x, mq.y)
				var mc := Color(1.0, 0.5, 0.2)
				mv.draw_line(mp3 - Vector2(10, 10), mp3 + Vector2(10, 10), mc, 2.0)
				mv.draw_line(mp3 - Vector2(10, -10), mp3 + Vector2(10, -10), mc, 2.0)
				mv.draw_arc(mp3, 14.0, 0, TAU, 20, mc, 1.5)
				if tq3.z > 0.0:
					mv.draw_line(Vector2(tq3.x, tq3.y), mp3,
						Color(mc.r, mc.g, mc.b, 0.5), 1.2)
				mv._label(mp3 + Vector2(18, 4), "%.1f km" % (
					mv.tank.global_position.distance_to(mv.tank.map_target) * 0.001),
					Color(1.0, 0.6, 0.3))
		var rvs3: Array = mv.tank.warhead_marks()
		for wi in rvs3.size():
			var wm3: Vector3 = Tank.mark_at(rvs3[wi])
			var wq := _globe_at(Vector2(wm3.x, wm3.z), org, rad, b)
			if wq.z <= 0.0:
				continue
			mv._rv_mark(Vector2(wq.x, wq.y), wi, rvs3[wi])
	# and the satellites, off the surface by their own altitude
	for sat in mv.get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		var q: Vector3 = (sat as Node3D).global_position
		var lift: float = 1.0 + Sim.altitude(q) / Sim.PLANET_R
		var p3 := _globe_at(Vector2(q.x, q.z), org, rad, b, lift)
		if p3.z <= 0.0:
			continue
		var here := Vector2(p3.x, p3.y)
		var hot: bool = sat == mv.sat_target
		var col2 := Color(1.0, 0.55, 0.35) if hot else Color(0.6, 0.9, 1.0)
		mv.draw_arc(here, 4.0, 0, TAU, 10, col2, 1.4)
		# a tether down to the ground under it, or an orbit reads as a contact
		var foot := _globe_at(Vector2(q.x, q.z), org, rad, b)
		mv.draw_line(here, Vector2(foot.x, foot.y),
			Color(col2.r, col2.g, col2.b, 0.35), 1.0)
	# the player, last so it is on top
	var me: Node3D = mv._me()
	if me != null:
		var a: Vector3 = me.global_position
		var lift2: float = 1.0 + maxf(Sim.altitude(a), 0.0) / Sim.PLANET_R
		var pa := _globe_at(Vector2(a.x, a.z), org, rad, b, lift2)
		if pa.z > 0.0:
			mv.draw_arc(Vector2(pa.x, pa.y), 6.0, 0, TAU, 14,
				Color(0.35, 1.0, 0.55), 2.0)
