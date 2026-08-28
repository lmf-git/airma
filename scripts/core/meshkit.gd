class_name MeshKit
## Low-poly procedural mesh helpers. Every face gets an explicit normal that is
## forced to point away from a supplied hull centre, so faceted airframes shade
## correctly no matter which order the section rings were authored in.

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func finish(st: SurfaceTool, surface: Material = null) -> ArrayMesh:
	var m: ArrayMesh = st.commit()
	if surface and m.get_surface_count() > 0:
		m.surface_set_material(0, surface)
	return m

## Add one triangle, oriented so its normal points away from `centre`.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3) -> void:
	var raw := (b - a).cross(c - a)
	if raw.length_squared() < 1e-12:
		return
	var n := raw.normalized()
	var mid := (a + b + c) / 3.0
	if n.dot(mid - centre) < 0.0:
		n = -n
	else:
		# Godot front faces wind clockwise as seen from outside, which is the
		# reverse of the right-handed order implied by the outward normal.
		var t := b
		b = c
		c = t
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)

## Add one triangle whose outward normal you already know. Deciding the facing
## by distance from a reference point is only ever as good as that point: on a
## concave planform -- a wing with a root extension, a cranked fin -- the
## centroid can sit outside the outline and panels come out inside out, which
## is a hole you look straight through.
static func tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var raw := (b - a).cross(c - a)
	if raw.length_squared() < 1e-12:
		return
	var nn := n.normalized()
	if raw.dot(nn) > 0.0:
		# Godot front faces wind clockwise seen from outside, the reverse of the
		# right-handed order implied by the outward normal
		var t := b
		b = c
		c = t
	st.set_normal(nn)
	st.add_vertex(a)
	st.set_normal(nn)
	st.add_vertex(b)
	st.set_normal(nn)
	st.add_vertex(c)

static func quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	tri_n(st, a, b, c, n)
	tri_n(st, a, c, d, n)

static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3) -> void:
	tri(st, a, b, c, centre)
	tri(st, a, c, d, centre)

## Fan-triangulate a convex ring.
static func face(st: SurfaceTool, loop: PackedVector3Array, centre: Vector3) -> void:
	for i in range(1, loop.size() - 1):
		tri(st, loop[0], loop[i], loop[i + 1], centre)

## A superellipse cross-section in the XY plane at depth `z`.
## `power` 2 = ellipse, <2 = diamond (stealth chine), >2 = boxy.
static func ring(hw: float, hh: float, cy: float, z: float, power: float, count: int = 12) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in count:
		var t := TAU * float(i) / float(count)
		var cs := cos(t)
		var sn := sin(t)
		var x := signf(cs) * pow(absf(cs), 2.0 / power) * hw
		var y := signf(sn) * pow(absf(sn), 2.0 / power) * hh
		pts.append(Vector3(x, y + cy, z))
	return pts

static func centroid(loop: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in loop:
		c += p
	return c / maxf(float(loop.size()), 1.0)

## Skin a stack of equal-sized rings into a hull.
## `inward` skins a tube you are meant to look *into* -- the well behind an
## intake lip -- where the visible side is the one facing the axis.
static func loft(st: SurfaceTool, rings: Array, centre: Vector3, cap_front := true,
		cap_back := true, inward := false) -> void:
	for s in range(rings.size() - 1):
		var a: PackedVector3Array = rings[s]
		var b: PackedVector3Array = rings[s + 1]
		# Which way a face points is decided by comparing its normal with the
		# line out from a reference point. One centre for the whole hull leaves
		# a face on anything long and thin -- a nacelle, an intake duct, a
		# nozzle -- almost perpendicular to that line, so the sign came down to
		# rounding and the odd panel ended up wound inside out: from some angles
		# you looked straight through the skin. The local section axis puts
		# every side face cleanly outward instead.
		var axis: Vector3 = (centroid(a) + centroid(b)) * 0.5
		var n := a.size()
		for i in n:
			var j := (i + 1) % n
			var qn := (a[j] - a[i]).cross(b[i] - a[i])
			if qn.length_squared() < 1e-12:
				continue
			qn = qn.normalized()
			var out_dir: Vector3 = (a[i] + a[j] + b[i] + b[j]) * 0.25 - axis
			if qn.dot(out_dir) < 0.0:
				qn = -qn
			if inward:
				qn = -qn
			quad_n(st, a[i], a[j], b[j], b[i], qn)
	if cap_front and rings.size() > 0:
		face(st, rings[0], centre)
	if cap_back and rings.size() > 1:
		face(st, rings[rings.size() - 1], centre)

## Extrude a 2D planform into a slab. `poly` is in the (u, v) plane; `thick`
## holds one half-thickness per polygon vertex so wings can taper to the tip.
static func prism(st: SurfaceTool, poly: PackedVector2Array, u: Vector3, v: Vector3,
		ext: Vector3, thick: PackedFloat32Array, origin := Vector3.ZERO) -> void:
	var n := poly.size()
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	for i in n:
		var p := origin + u * poly[i].x + v * poly[i].y
		top.append(p + ext * thick[i])
		bot.append(p - ext * thick[i])
	# Which way the outline is wound, so an edge normal can be turned out of the
	# shape rather than away from a centroid that may not even be inside it.
	var area := 0.0
	for i in n:
		var j := (i + 1) % n
		area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	var turn := 1.0 if area >= 0.0 else -1.0
	for i in n:
		var j := (i + 1) % n
		var d := poly[j] - poly[i]
		var e := Vector2(d.y, -d.x) * turn
		if e.length_squared() < 1e-12:
			continue
		e = e.normalized()
		quad_n(st, top[i], top[j], bot[j], bot[i], (u * e.x + v * e.y).normalized())
	# and the two flat sides face along the thickness, by construction
	var up := ext.normalized()
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		for i in range(1, n - 1):
			tri_n(st, top[0], top[i], top[i + 1], up)
			tri_n(st, bot[0], bot[i], bot[i + 1], -up)
	else:
		var k := 0
		while k < idx.size():
			tri_n(st, top[idx[k]], top[idx[k + 1]], top[idx[k + 2]], up)
			tri_n(st, bot[idx[k]], bot[idx[k + 1]], bot[idx[k + 2]], -up)
			k += 3

static func box(st: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var h := size * 0.5
	var v := []
	for i in 8:
		v.append(at + Vector3(
			h.x * (1.0 if (i & 1) else -1.0),
			h.y * (1.0 if (i & 2) else -1.0),
			h.z * (1.0 if (i & 4) else -1.0)))
	var f := [[0,1,3,2],[4,5,7,6],[0,1,5,4],[2,3,7,6],[0,2,6,4],[1,3,7,5]]
	for q in f:
		quad(st, v[q[0]], v[q[1]], v[q[2]], v[q[3]], at)

## Tapered tube along -Z (nozzles, missile bodies, gear struts).
static func cone(st: SurfaceTool, r0: float, r1: float, z0: float, z1: float,
		at: Vector3, seg := 10, caps := true) -> void:
	var rings := [ring(r0, r0, 0.0, z0, 2.0, seg), ring(r1, r1, 0.0, z1, 2.0, seg)]
	for i in rings.size():
		var r: PackedVector3Array = rings[i]
		for k in r.size():
			r[k] = r[k] + at
		rings[i] = r
	loft(st, rings, at + Vector3(0, 0, (z0 + z1) * 0.5), caps, caps)

static func mat(albedo: Color, rough := 0.55, metal := 0.25, emis := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	if emis != Color.BLACK:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = 2.0
	return m

static var _paint_shader: Shader = null

## Painted surface with procedural panel lines and mottling. Everything in this
## project is untextured geometry, so this is what stops large flat areas like a
## wing or a hull reading as a single dead colour.
static func panelled(base: Color, rough := 0.42, metal := 0.06, panel := 1.7) -> ShaderMaterial:
	if _paint_shader == null:
		_paint_shader = Shader.new()
		_paint_shader.code = """
shader_type spatial;
uniform vec4 base_col : source_color = vec4(0.5, 0.5, 0.55, 1.0);
uniform float rough_v = 0.42;
uniform float metal_v = 0.06;
uniform float panel_size = 1.7;
varying vec3 mpos;
varying vec3 mnorm;
float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
void vertex() {
	mpos = VERTEX;
	mnorm = NORMAL;
}
void fragment() {
	// panel seams on a model space grid, weighted away from the face normal so
	// lines run along the surface instead of crawling over it
	vec3 g = abs(fract(mpos / panel_size) - 0.5);
	vec3 w = 1.0 - abs(normalize(mnorm));
	float seam = max(max(g.x * w.x, g.y * w.y), g.z * w.z);
	float line = smoothstep(0.42, 0.499, seam);
	// coarse mottling and a fine grain so big surfaces are not dead flat
	float m = hash13(floor(mpos * 1.4));
	float f = hash13(floor(mpos * 9.0));
	vec3 c = base_col.rgb * (1.0 - line * 0.17) * (0.93 + m * 0.10 + f * 0.035);
	ALBEDO = c;
	ROUGHNESS = clamp(rough_v + line * 0.18 + m * 0.06, 0.0, 1.0);
	METALLIC = metal_v;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _paint_shader
	m.set_shader_parameter("base_col", base)
	m.set_shader_parameter("rough_v", rough)
	m.set_shader_parameter("metal_v", metal)
	m.set_shader_parameter("panel_size", panel)
	return m

static func mi(mesh: Mesh, name := "Mesh") -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = name
	n.mesh = mesh
	return n
