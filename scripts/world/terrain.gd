class_name Terrain
extends Node3D
## Modular chunked terrain. The map is covered by concentric rings of square
## chunks; every ring uses a coarser cell size than the one inside it. All of
## them sample the same analytic height and biome fields, so neighbouring
## chunks line up exactly and the biome bands run continuously across chunk
## borders. Vertical skirts hide the T-junctions where two rings meet.

const CELLS := 16                     # cells per chunk edge, every ring
const BASE_CELL := 30.0               # innermost cell size
const OUT := 4                        # chunks from the middle to the edge of a ring
const LEVELS := 7                     # each level doubles the cell size

## Every ring doubles the cell size and reaches OUT chunks out, so the hole in
## the middle of a ring is exactly two of that ring's chunks and the finer ring
## inside fills it precisely. Getting this wrong leaves coarse chunks lying over
## fine ones, which is what tore holes in the mountains.
static func ring_table() -> Array:
	var out: Array = []
	var cell := BASE_CELL
	var inner := 0.0
	for i in LEVELS:
		var span := cell * float(CELLS)
		var n: int = OUT if i < LEVELS - 1 else 3
		out.append({"cell": cell, "span": span, "n": n, "inner": inner,
			"coverage": span * float(n), "shadow": i == 0})
		inner = span * float(n)
		cell *= 2.0
	return out

var _mat: ShaderMaterial
var stats := {"chunks": 0, "tris": 0, "seam": 0.0}

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// How far out the fine grain is worth drawing. Beyond this the ground goes back
// to flat biome colour, which is all you can resolve anyway and costs nothing.
uniform float detail_fade = 1100.0;

varying vec3 wpos;
varying vec3 wnrm;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x),
			   mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// the biome colour is authored in sRGB and baked per vertex
	vec3 base = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float d = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(0.0, detail_fade, d);
	float grain = vnoise(wpos.xz * 0.42) * 0.6 + vnoise(wpos.xz * 1.7) * 0.4;
	float patch = vnoise(wpos.xz * 0.031);
	// large scale mottling everywhere, fine grain only where it can be resolved
	base *= 0.90 + 0.20 * patch;
	base *= mix(1.0, 0.80 + 0.40 * grain, near * 0.85);
	// Anything steep enough sheds its cover and shows rock -- but a chunk skirt
	// is a vertical wall dropped at the tile edge to hide the T-junction, and
	// treating it as a cliff painted a dark band down every seam in the map.
	// Fade the rock back out as the face approaches vertical, which real ground
	// never is and a skirt always is.
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float rock_amt = smoothstep(0.38, 0.72, slope) * (1.0 - smoothstep(0.88, 0.99, slope));
	vec3 rock = vec3(0.20, 0.19, 0.18) * (0.75 + 0.5 * grain);
	base = mix(base, rock, rock_amt * 0.7);
	ALBEDO = base;
	ROUGHNESS = 0.95 - 0.12 * grain;
	METALLIC = 0.0;
}
"""

## Ground material: biome colour from the vertices, texture from a couple of
## octaves of value noise in world space. Flat vertex colour reads as a painted
## backdrop at low level, and gives a fast jet nothing to sweep past.
func _ground_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func build() -> void:
	_mat = _ground_material()

	for r in ring_table():
		_ring(r["inner"], r["n"], r["cell"], r["shadow"])
	_water()

## Lay chunks over the square annulus for one level.
func _ring(inner: float, n: int, cell: float, shadow: bool) -> void:
	var span := cell * float(CELLS)
	for cz in range(-n, n):
		for cx in range(-n, n):
			var x0 := float(cx) * span
			var z0 := float(cz) * span
			# the hole is an exact whole number of chunks, so this never
			# leaves a partial chunk overlapping the finer ring
			if inner > 0.0 and absf(x0) < inner and absf(z0) < inner:
				continue
			_chunk(x0, z0, cell, shadow, span * float(n))

func _chunk(x0: float, z0: float, cell: float, shadow: bool, coverage: float) -> void:
	var n := CELLS + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	for j in n:
		for i in n:
			h[j * n + i] = Sim.height_at(x0 + i * cell, z0 + j * cell)
	_stitch(h, n, x0, z0, cell, coverage)
	var st := MeshKit.begin()
	for j in CELLS:
		for i in CELLS:
			var a := Vector3(x0 + i * cell, h[j * n + i], z0 + j * cell)
			var b := Vector3(x0 + (i + 1) * cell, h[j * n + i + 1], z0 + j * cell)
			var c := Vector3(x0 + (i + 1) * cell, h[(j + 1) * n + i + 1], z0 + (j + 1) * cell)
			var d := Vector3(x0 + i * cell, h[(j + 1) * n + i], z0 + (j + 1) * cell)
			_face(st, a, b, c)
			_face(st, a, c, d)
	_skirt(st, x0, z0, cell, h, n)
	var mi := MeshKit.mi(MeshKit.finish(st, _mat), "C%d_%d" % [int(x0), int(z0)])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var resid := 0.0
	if absf(z0 + coverage) < cell * 0.01:
		for i in range(1, n - 1, 2):
			resid = maxf(resid, absf(h[i] - (h[i - 1] + h[i + 1]) * 0.5))
	if absf(x0 + coverage) < cell * 0.01:
		for j in range(1, n - 1, 2):
			resid = maxf(resid, absf(h[j * n] - (h[(j - 1) * n] + h[(j + 1) * n]) * 0.5))
	stats["seam"] = maxf(float(stats.get("seam", 0.0)), resid)
	stats["chunks"] += 1
	stats["tris"] += CELLS * CELLS * 2

## Stitch the edges that face a coarser ring.
##
## The ring outside this one has cells twice as wide, so along a shared boundary
## it has a vertex only at every second one of ours. Its edge therefore runs
## straight past our odd vertices, and wherever the ground is not flat the two
## surfaces part company: measured across this map, ten metres on average and
## two hundred and fifty at worst. Skirts were hiding that rather than fixing
## it. Dropping our odd boundary vertices onto the chord between their
## neighbours makes the two edges the same line, and the gap becomes zero by
## construction rather than by being covered up.
func _stitch(h: PackedFloat32Array, n: int, x0: float, z0: float,
		cell: float, coverage: float) -> void:
	var span := cell * float(CELLS)
	var eps := cell * 0.01
	# west and east columns
	if absf(x0 + coverage) < eps:
		for j in range(1, n - 1, 2):
			h[j * n] = (h[(j - 1) * n] + h[(j + 1) * n]) * 0.5
	if absf(x0 + span - coverage) < eps:
		for j in range(1, n - 1, 2):
			h[j * n + n - 1] = (h[(j - 1) * n + n - 1] + h[(j + 1) * n + n - 1]) * 0.5
	# north and south rows
	if absf(z0 + coverage) < eps:
		for i in range(1, n - 1, 2):
			h[i] = (h[i - 1] + h[i + 1]) * 0.5
	if absf(z0 + span - coverage) < eps:
		for i in range(1, n - 1, 2):
			h[(n - 1) * n + i] = (h[(n - 1) * n + i - 1] + h[(n - 1) * n + i + 1]) * 0.5

## A vertical curtain around the chunk edge so a coarser neighbour cannot show
## daylight through the seam.
func _skirt(st: SurfaceTool, x0: float, z0: float, cell: float, h: PackedFloat32Array, n: int) -> void:
	var drop := cell * 3.0
	for i in CELLS:
		var edges := [
			[Vector3(x0 + i * cell, h[i], z0), Vector3(x0 + (i + 1) * cell, h[i + 1], z0)],
			[Vector3(x0 + (i + 1) * cell, h[CELLS * n + i + 1], z0 + CELLS * cell),
			 Vector3(x0 + i * cell, h[CELLS * n + i], z0 + CELLS * cell)],
			[Vector3(x0, h[(i + 1) * n], z0 + (i + 1) * cell), Vector3(x0, h[i * n], z0 + i * cell)],
			[Vector3(x0 + CELLS * cell, h[i * n + CELLS], z0 + i * cell),
			 Vector3(x0 + CELLS * cell, h[(i + 1) * n + CELLS], z0 + (i + 1) * cell)],
		]
		for e in edges:
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			var a2 := a - Vector3(0, drop, 0)
			var b2 := b - Vector3(0, drop, 0)
			var col := Sim.biome_colour(a.x, a.z, a.y, 1.0).darkened(0.25)
			for v in [a, b, b2, a, b2, a2]:
				st.set_normal(Vector3.UP)
				st.set_color(col)
				st.add_vertex(v)

func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.set_color(_tint(v, nrm.y))
		st.add_vertex(v)

func _tint(v: Vector3, slope: float) -> Color:
	var c := Sim.biome_colour(v.x, v.z, v.y, slope)
	# roads are painted into the terrain itself, so they never z-fight or float
	if v.y > Sim.WATER_LEVEL:
		# a wide, strong stain under every road and street: at altitude the
		# carriageway mesh is sub-pixel, so this is what actually draws the
		# network from the air
		var rd := Sim.road_distance(v.x, v.z)
		if rd < 46.0:
			c = c.lerp(Color(0.19, 0.185, 0.175), (1.0 - smoothstep(7.0, 46.0, rd)) * 0.78)
	var nz := Sim.noise_det.get_noise_2d(v.y * 7.3, slope * 1000.0) * 0.03
	return Color(clampf(c.r + nz, 0, 1), clampf(c.g + nz, 0, 1), clampf(c.b + nz, 0, 1))

func _water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(Sim.WORLD_HALF * 2.4, Sim.WORLD_HALF * 2.4)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.19, 0.28, 0.86)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.metallic = 0.45
	m.rim_enabled = true
	m.rim = 0.7
	# The sea sorts before every other transparent thing. It is a single mesh
	# the width of the world, so its sort origin is nowhere near the piece of
	# water you are actually looking at, and without this it happily draws over
	# splashes, explosions and anything else at the surface.
	m.render_priority = -8
	var mi := MeshKit.mi(pm, "Water")
	mi.material_override = m
	mi.position = Vector3(0, Sim.WATER_LEVEL, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
