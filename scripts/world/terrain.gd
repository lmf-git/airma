class_name Terrain
extends Node3D
## Modular chunked terrain, as a quadtree over the whole world.
##
## This was concentric rings around the eye, and rings turn out to be a quadtree
## with the tree left implicit: forty-eight chunks per ring is what a distance
## rule with K = 2 produces anyway. What the rings could not do is notice that
## most of a six hundred kilometre map is flat sea, and they had to be dragged
## along behind the aeroplane -- so every chunk boundary moved when you did, and
## chunks kept the edge stitching they were built with for a centre they were no
## longer at.
##
## The tree is anchored to the world origin instead. A node's identity is its
## depth and grid index, which never change, so flying does not shift a single
## boundary; a node is rebuilt only when the detail it deserves changes. Nodes
## split on measured error against the height field, so open water and plains
## stop early and ridge lines keep going. All of them sample the same analytic
## height and biome fields, so neighbouring chunks line up exactly and the
## biome bands run continuously across chunk borders.

const CELLS := 16                     # cells per chunk edge, every ring
## Cells across a chunk at the level above, which is what the morph target is
## interpolated on.
const HALF_CELLS := 8
## Innermost cell size. This is the finest detail the ground can hold, and it is
## also the finest anything *painted into* the ground can hold — a road stain
## narrower than a cell has no vertices to land on and flickers with the grid.
## Halved from 30 m, with a level added so the outermost ring still reaches the
## same distance: 15 x 2^7 is the same 1920 m cell the old outer ring used.
const BASE_CELL := 15.0
## The world is one square, halved and halved again wherever the ground is
## worth more triangles than it is getting. A leaf at depth d has a span of
## ROOT_SPAN / 2^d and always CELLS cells across it, so depth is cell size.
## Thirteen halvings of 1966 km land on a 240 m leaf drawn at BASE_CELL.
const MAX_DEPTH := 13
## 15 x 16 x 8192. Root covers +-983 km, which is the +-600 km world with room
## to spare, and every grid at every depth is a whole number of BASE_CELL steps
## from the world origin -- which is what lets a fine edge land exactly on a
## coarse one without any snapping.
const ROOT_SPAN := BASE_CELL * float(CELLS) * 8192.0

## A node stops splitting once the eye is further away than this many of its own
## spans. This alone is the old ring scheme: rings of 48 chunks are exactly what
## a quadtree with K = 2 produces, which is why swapping one for the other buys
## nothing on its own. The saving is in the error test below.
const SPLIT_K := 2.0
## How far the drawn surface has to stand off the real one, in metres, before
## subdividing it is worth the triangles. Ground flatter than this stops early
## however close you get -- there is nothing there for the extra vertices to
## describe.
##
## An absolute height, not a fraction of the node's span. Scaled by span, the
## root -- 983 km across, over a world whose entire relief is two kilometres --
## could never clear its own threshold, so the tree never subdivided at all and
## the whole world came out as four chunks.
const ERR_ABS := 0.4

## How far the drawn surface of a node stands off the real height field, in
## metres. This is what makes the quadtree worth having over the rings: sea and
## plains have almost none of it and stop subdividing early, while a ridge line
## keeps splitting until it is resolved. It is a property of the height field
## alone -- no eye, no frame -- so it is computed once per node and kept.
static var _err: Dictionary = {}
## The highest ground in each node, so the seabed can be told from the land.
static var _top: Dictionary = {}
## How much less a node that is entirely under water is worth subdividing. The
## error metric measures the seabed as faithfully as it measures a mountain
## range, and spent the same triangles on it -- for relief that is under a
## couple of hundred metres of water and, from a submarine, in the dark.
const SEABED_DETAIL := 0.12

static func span_at(depth: int) -> float:
	return ROOT_SPAN / float(1 << depth)

static func node_error(depth: int, ix: int, iz: int) -> float:
	var k := "%d,%d,%d" % [depth, ix, iz]
	if _err.has(k):
		return float(_err[k])
	var span := span_at(depth)
	var cell := span / float(CELLS)
	var x0 := float(ix) * span
	var z0 := float(iz) * span
	var n := CELLS + 1
	var g := PackedFloat32Array()
	g.resize(n * n)
	for j in n:
		for i in n:
			g[j * n + i] = Sim.height_at(x0 + float(i) * cell, z0 + float(j) * cell)
	# At a cell's centre both of its triangles read the mean of the two corners
	# the shared diagonal runs through, so the drawn height there is exact and
	# needs no interpolation. Every other cell is plenty to find a ridge.
	var e := 0.0
	var top := -1e9
	for j2 in range(0, CELLS, 2):
		for i2 in range(0, CELLS, 2):
			var drawn: float = (g[j2 * n + i2] + g[(j2 + 1) * n + i2 + 1]) * 0.5
			var truth := Sim.height_at(x0 + (float(i2) + 0.5) * cell,
				z0 + (float(j2) + 0.5) * cell)
			e = maxf(e, absf(truth - drawn))
	for gv in g:
		top = maxf(top, gv)
	_err[k] = e
	_top[k] = top
	return e

## The highest ground in a node. Asked after `node_error`, which is what fills
## it in.
static func node_top(depth: int, ix: int, iz: int) -> float:
	var k := "%d,%d,%d" % [depth, ix, iz]
	if not _top.has(k):
		node_error(depth, ix, iz)
	return float(_top.get(k, 0.0))

## A node that is already subdivided has to be got clearly further away before
## it merges again, and one that is not has to be got clearly closer before it
## splits. Without this the tree re-decides on exactly the same threshold every
## time the viewer moves, so anything sitting near one flips back and forth --
## measured, a helicopter orbiting a 900 m circle rebuilt three thousand chunks
## in two minutes and the ground visibly churned the whole time.
const HYST := 1.45

## Which nodes were subdivided last time the tree was walked. Read during a walk
## and only replaced at the end of it, so every decision inside one walk -- the
## descent itself and every neighbour probe -- is made against the same state.
var _was_split: Dictionary = {}

## Does this node hand its ground to four children?
func splits(depth: int, ix: int, iz: int, eye: Vector3) -> bool:
	if depth >= MAX_DEPTH:
		return false
	var span := span_at(depth)
	var x0 := float(ix) * span
	var z0 := float(iz) * span
	# distance from the eye to the node's footprint, zero inside it
	var dx := maxf(maxf(x0 - eye.x, eye.x - (x0 + span)), 0.0)
	var dz := maxf(maxf(z0 - eye.z, eye.z - (z0 + span)), 0.0)
	var dist := sqrt(dx * dx + dz * dz)
	var k := SPLIT_K
	if _was_split.has(_node_key(depth, ix, iz)):
		k *= HYST
	if dist >= k * span:
		return false
	# The error decides *whether* a node is worth subdividing, not how close you
	# have to get before it is.
	#
	# Scaling the split distance by the error read well and quietly wrecked the
	# geomorph: a node whose ground is gentle handed over to its children at a
	# fraction of the distance rule, so they arrived barely blended and the
	# switch was plainly visible -- measured, the morph was only 61% finished on
	# average and 4% at worst. Made a yes-or-no test, every hand-over that
	# happens at all happens at exactly SPLIT_K spans, which is the distance the
	# blend is built around, so it is always complete.
	var e := node_error(depth, ix, iz)
	# Nothing above the surface anywhere in it: this is seabed, and it does not
	# earn the triangles that the same relief above water would.
	if node_top(depth, ix, iz) < Sim.WATER_LEVEL - 1.0:
		e *= SEABED_DETAIL
	return e > ERR_ABS

static func _node_key(depth: int, ix: int, iz: int) -> String:
	return "%d,%d,%d" % [depth, ix, iz]

var _mat: ShaderMaterial
var mask_img: Image = null
var stats := {"chunks": 0, "tris": 0, "seam": 0.0}

const GROUND_SHADER := """
shader_type spatial;
// Drawn from underneath as well. Terrain faces up, so with back faces culled
// every triangle of the seabed is a back face when you are below it: from a
// submarine you looked straight through the ground at the sky.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// How far out the fine grain is worth drawing. Beyond this the ground goes back
// to flat biome colour, which is all you can resolve anyway and costs nothing.
uniform float detail_fade = 1100.0;

// Roads and made ground, baked once into a mask and sampled per fragment.
//
// These used to be painted into the vertex colours, which meant the sharpest a
// road could ever be was one terrain cell. The rings are centred on the
// airfield, so a town four kilometres out is drawn with 120 m cells and one ten
// kilometres out with 240 m — against a street grid of 128 m. Northgate had
// roughly one vertex every two blocks to say "street" with. No cell size fixes
// that: 15 m cells out at ten kilometres is three and a half million triangles
// for a single ring. In the mask it is one texture fetch and the geometry stops
// mattering.
uniform sampler2D ground_mask : filter_linear_mipmap, source_color;
uniform float mask_half = 18000.0;
// Where that box is. It used to be nailed to the world origin, which was fine
// while everything anyone had built stood around one airfield; with settlements
// three hundred kilometres away it follows whichever part of the world you are
// actually in.
uniform vec2 mask_centre = vec2(0.0, 0.0);
uniform vec3 tarmac : source_color = vec3(0.135, 0.133, 0.140);
// Concrete and hardstanding, not wet earth. At 0.335 this was darker than the
// grass it replaced, so every town read as a stain on the map rather than as a
// built-up place.
uniform vec3 made_ground : source_color = vec3(0.56, 0.55, 0.53);

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

// Which detail level draws a chunk is decided by how far it is from the eye,
// and the change from one level to the next is a visible jump in the ground
// unless the finer one arrives already shaped like the coarser one. UV2.x
// carries, per vertex, the difference between this chunk's own height there and
// the height its parent level draws; blending that in across the band where the
// switch happens makes the two identical at the moment of the change, and then
// unfolds the detail as you close on it.
//
// The blend is worked out per vertex from that vertex's own distance rather
// than once per chunk, so two chunks meeting along an edge agree on it exactly
// and the morph cannot tear a seam open. SPLIT_K matches the constant the
// quadtree splits on.
// The chunk's own width rides in UV2.y rather than coming down as a per
// instance uniform, so the mesh carries everything the morph needs and there is
// no second channel to get out of step with it.
const float SPLIT_K = 2.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float lo = SPLIT_K * UV2.y;
	float hi = 2.0 * lo;
	float m = clamp((distance(wp.xz, CAMERA_POSITION_WORLD.xz) - lo)
		/ max(hi - lo, 1.0), 0.0, 1.0);
	VERTEX.y += m * UV2.x;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// underside: the stored normal points up, so light it with the normal
	// turned round rather than as though the sun were shining up through it
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
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
	// Built-up ground first, then the roads over it, so a street reads as a
	// dark line on pavement rather than as a dark line on grass.
	vec2 muv = (wpos.xz - mask_centre) / (mask_half * 2.0) + vec2(0.5);
	float road_amt = 0.0;
	float town_amt = 0.0;
	if (muv.x > 0.0 && muv.x < 1.0 && muv.y > 0.0 && muv.y < 1.0) {
		vec2 mk = texture(ground_mask, muv).rg;
		road_amt = mk.r;
		town_amt = mk.g;
	}
	float grit = (grain - 0.5) * 0.09;
	base = mix(base, pow(made_ground, vec3(2.2)) * (1.0 + grit), town_amt * 0.78);
	base = mix(base, pow(tarmac, vec3(2.2)) * (1.0 + grit * 0.5), road_amt * 0.88);
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
	m.set_shader_parameter("mask_half", MASK_HALF)
	m.set_shader_parameter("mask_centre", mask_centre)
	m.set_shader_parameter("ground_mask", _bake_ground_mask())
	return m

const MASK_N := 4096                  # texels across the inhabited box
const MASK_HALF := 18000.0            # and how far that box reaches

## Rasterise the road network and the town footprints into one mask: red is
## tarmac, green is made ground.
##
## Stamped segment by segment rather than sampled point by point. Asking the
## distance field for every one of sixteen million texels would take minutes;
## drawing 164 capsules into a byte array takes a moment, and it is the same
## picture. The resolution works out at 8.8 m to a texel, which is what a ten
## metre street needs to read as a line rather than as a suggestion.
## Which part of the world the mask currently covers.
var mask_centre := Vector2.ZERO

func _bake_ground_mask() -> ImageTexture:
	var n := MASK_N
	var t0 := Time.get_ticks_msec()
	var cached: Variant = WorldBake.get_baked("ground_mask_%d_%d" % [
		int(mask_centre.x), int(mask_centre.y)])
	if cached is PackedByteArray and (cached as PackedByteArray).size() == n * n * 2:
		return _mask_texture(cached, n, t0)
	var buf := PackedByteArray()
	buf.resize(n * n * 2)
	var tpm: float = float(n) / (MASK_HALF * 2.0)     # texels per metre
	# made ground under the settlements
	for pad in Sim._town_pads:
		var pc: Vector2 = pad["c"]
		var pr: float = pad["r"]
		if not _in_box(pc, pr * 1.4):
			continue
		_stamp_disc(buf, n, tpm, pc - mask_centre, pr * 1.02, pr * 1.32, 1)
	# then the network: trunk roads wide, streets narrow
	for r in Sim.ROADS:
		if not _in_box(r[0], 40.0) and not _in_box(r[1], 40.0):
			continue
		_stamp_capsule(buf, n, tpm, (r[0] as Vector2) - mask_centre,
			(r[1] as Vector2) - mask_centre, 9.0, 30.0, 0)
	for r in Sim._segments:
		if not _in_box(r[0], 20.0) and not _in_box(r[1], 20.0):
			continue
		_stamp_capsule(buf, n, tpm, (r[0] as Vector2) - mask_centre,
			(r[1] as Vector2) - mask_centre, 5.0, 13.0, 0)
	var road_px := 0
	var town_px := 0
	for k in range(0, buf.size(), 2):
		if buf[k] > 96:
			road_px += 1
		if buf[k + 1] > 96:
			town_px += 1
	stats["mask_road_px"] = road_px
	stats["mask_town_px"] = town_px
	stats["mask_m_per_texel"] = snappedf(1.0 / tpm, 0.01)
	WorldBake.put("ground_mask_%d_%d" % [int(mask_centre.x), int(mask_centre.y)],
		buf)
	return _mask_texture(buf, n, t0)

func _mask_texture(buf: PackedByteArray, n: int, t0: int) -> ImageTexture:
	stats["mask_ms"] = Time.get_ticks_msec() - t0
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RG8, buf)
	# A second 33 MB copy is only worth carrying when something is going to
	# measure it; in a normal session the GPU has the only copy it needs.
	if OS.has_feature("headless") or OS.is_debug_build():
		mask_img = img.duplicate()      # un-mipmapped, for the harness
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Move the painted box to another part of the world. Cheap when it is already
## there; a re-bake and a texture swap when it is not, and the result is kept on
## disk per centre so each region is only ever rasterised once.
func set_mask_centre(c: Vector2) -> void:
	if mask_centre.distance_to(c) < 1.0 or _mat == null:
		return
	mask_centre = c
	_mat.set_shader_parameter("mask_centre", mask_centre)
	_mat.set_shader_parameter("ground_mask", _bake_ground_mask())

## What the ground actually shows at a world point: red tarmac, green made
## ground, straight out of the baked mask.
func mask_at(x: float, z: float) -> Vector2:
	if mask_img == null:
		return Vector2.ZERO
	var tpm: float = float(MASK_N) / (MASK_HALF * 2.0)
	var i := clampi(int((x - mask_centre.x + MASK_HALF) * tpm), 0, MASK_N - 1)
	var j := clampi(int((z - mask_centre.y + MASK_HALF) * tpm), 0, MASK_N - 1)
	var c := mask_img.get_pixel(i, j)
	return Vector2(c.r, c.g)

## World metres to texel, clamped to the image.
func _to_texel(tpm: float, n: int, v: float) -> int:
	return clampi(int((v + MASK_HALF) * tpm), 0, n - 1)

## Is any of this worth stamping, or is it in a different part of the world?
## Clamping put every distant town and road on the edge texels of the box, as a
## smear down one side of the map.
func _in_box(c: Vector2, r: float) -> bool:
	return absf(c.x - mask_centre.x) < MASK_HALF + r \
		and absf(c.y - mask_centre.y) < MASK_HALF + r

func _stamp_disc(buf: PackedByteArray, n: int, tpm: float, c: Vector2,
		solid: float, fade: float, channel: int) -> void:
	var lo_x := _to_texel(tpm, n, c.x - fade)
	var hi_x := _to_texel(tpm, n, c.x + fade)
	var lo_z := _to_texel(tpm, n, c.y - fade)
	var hi_z := _to_texel(tpm, n, c.y + fade)
	for j in range(lo_z, hi_z + 1):
		var wz := float(j) / tpm - MASK_HALF
		for i in range(lo_x, hi_x + 1):
			var wx := float(i) / tpm - MASK_HALF
			var d := Vector2(wx - c.x, wz - c.y).length()
			var v := 1.0 - smoothstep(solid, fade, d)
			if v <= 0.0:
				continue
			var idx := (j * n + i) * 2 + channel
			buf[idx] = maxi(buf[idx], int(clampf(v, 0.0, 1.0) * 255.0))

func _stamp_capsule(buf: PackedByteArray, n: int, tpm: float, a: Vector2,
		b: Vector2, solid: float, fade: float, channel: int) -> void:
	var lo_x := _to_texel(tpm, n, minf(a.x, b.x) - fade)
	var hi_x := _to_texel(tpm, n, maxf(a.x, b.x) + fade)
	var lo_z := _to_texel(tpm, n, minf(a.y, b.y) - fade)
	var hi_z := _to_texel(tpm, n, maxf(a.y, b.y) + fade)
	for j in range(lo_z, hi_z + 1):
		var wz := float(j) / tpm - MASK_HALF
		for i in range(lo_x, hi_x + 1):
			var wx := float(i) / tpm - MASK_HALF
			var q := Vector2(wx, wz)
			var d := Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q)
			var v := 1.0 - smoothstep(solid, fade, d)
			if v <= 0.0:
				continue
			var idx := (j * n + i) * 2 + channel
			buf[idx] = maxi(buf[idx], int(clampf(v, 0.0, 1.0) * 255.0))

## Live leaves, keyed by depth and grid index plus the depths of the four
## neighbours -- because those decide how the edges are conformed, and a node
## whose neighbour has changed detail needs rebuilding even though its own
## detail has not.
var _live: Dictionary = {}
var _centre := Vector3(1e12, 0.0, 1e12)
var _pending: Array = []
var _retire: Dictionary = {}
## The batch currently out with the worker pool: the jobs, a slot per job for
## what comes back, and the group id to poll.
var _batch: Array = []
var _batch_out: Array = []
var _batch_id := -1
var _batch_done := false
## Set by the churn harness: base key -> how many times it has been built.
var debug_builds: Dictionary = {}
var debug_count := false

## Chunks that were live and are not any more, kept built and hidden rather than
## thrown away.
##
## A viewer that crosses a detail threshold and crosses back -- a helicopter
## orbiting a point, a circuit round the field, anything that is not flying in a
## straight line -- asks for exactly the same geometry it just discarded.
## Rebuilding it is 289 height samples and a mesh, and doing that continuously
## is what "the terrain reloads while I am looking at it" is. Coming back is now
## free: the mesh is still there, it is just hidden.
## Sized from the working set rather than guessed: a lap of a tight orbit
## touches about 760 distinct chunks, and a shelf smaller than that evicts the
## far side of the circle before you come round to it again.
const CACHE_MAX := 1200

var _cache: Dictionary = {}
var _cache_age: Array = []
var _retire_key: Dictionary = {}

func build() -> void:
	prepare()
	flush_pending()

## Everything that has to happen before a single chunk can be built, and the
## queue filled -- but nothing built. The loading screen pumps `flush_pending`
## from there so the window keeps painting; `build` is the same thing in one
## blocking go, for the harnesses.
func prepare() -> void:
	# The error table is a property of the height field and of nothing else, so
	# it survives between runs. It keeps growing as you fly somewhere the tree
	# has not had to think about before, and whatever it has learned by the end
	# of the session goes back to disk.
	var cached: Variant = WorldBake.get_baked("node_err")
	if cached is Dictionary and not (cached as Dictionary).is_empty():
		_err = cached
	_mat = _ground_material()
	recentre(Vector3.ZERO)
	_water()

## How much of the queue is done, 0 to 1.
func build_progress() -> float:
	var left := _pending.size() + _batch.size()
	var done := _live.size()
	return float(done) / maxf(float(done + left), 1.0)

## The depth of the leaf covering a point. Used to ask what the neighbour across
## an edge is drawn at, which is the only thing an edge needs to know.
func depth_at(x: float, z: float, eye: Vector3) -> int:
	var d := 1
	var s := span_at(1)
	var ix: int = clampi(int(floor(x / s)), -1, 0)
	var iz: int = clampi(int(floor(z / s)), -1, 0)
	while splits(d, ix, iz, eye):
		d += 1
		s = span_at(d)
		ix = int(floor(x / s))
		iz = int(floor(z / s))
	return d

## The leaves that should exist for this eye position, by descent from the four
## root quadrants.
func _wanted(eye: Vector3) -> Dictionary:
	var out: Dictionary = {}
	var opened: Dictionary = {}
	var stack: Array = [[1, -1, -1], [1, 0, -1], [1, -1, 0], [1, 0, 0]]
	while not stack.is_empty():
		var nd: Array = stack.pop_back()
		var d: int = nd[0]
		var ix: int = nd[1]
		var iz: int = nd[2]
		if splits(d, ix, iz, eye):
			opened[_node_key(d, ix, iz)] = true
			for c in 4:
				stack.append([d + 1, ix * 2 + (c & 1), iz * 2 + (c >> 1)])
			continue
		var span := span_at(d)
		var cell := span / float(CELLS)
		var x0 := float(ix) * span
		var z0 := float(iz) * span
		var half := span * 0.5
		var step := cell * 0.5
		# A coarser neighbour spans this whole edge, so one probe just outside
		# the middle of it settles the question. Finer neighbours conform to us
		# and need nothing from this side.
		# Clamped to our own depth. Only a *coarser* neighbour changes this
		# chunk's geometry -- a finer one conforms to us and we do nothing about
		# it -- so recording its exact depth in the key meant a leaf next to a
		# detailed region was rebuilt every time any of that region shifted a
		# level, for a mesh that came out identical.
		var raw := [
			depth_at(x0 - step, z0 + half, eye),
			depth_at(x0 + span + step, z0 + half, eye),
			depth_at(x0 + half, z0 - step, eye),
			depth_at(x0 + half, z0 + span + step, eye),
		]
		var nb: Array = []
		# Which edges face a *finer* neighbour. That neighbour conforms its edge
		# to ours as we draw it, so ours may not move: if this chunk morphs an
		# edge the fine side has already matched itself to, the two part company
		# and the seam opens by as much as the morph -- measured, a kilometre.
		var fine := 0
		for e in 4:
			nb.append(mini(int(raw[e]), d))
			if int(raw[e]) > d:
				fine |= 1 << e
		out["%d:%d:%d:%d,%d,%d,%d:%d" % [d, ix, iz, nb[0], nb[1], nb[2], nb[3],
			fine]] = [d, ix, iz, nb, fine]
	_was_split = opened
	return out

## Move the viewer. Cheap when nothing has changed: the wanted set is compared
## against what is live and only the difference is touched. Because the tree is
## anchored to the world and not to the eye, "nothing has changed" is the
## overwhelmingly common case -- flying a straight line across open sea rebuilds
## nothing at all.
func recentre(eye: Vector3, immediate := false) -> void:
	if not immediate and _centre.distance_squared_to(eye) < 90000.0:
		return
	var want := _wanted(eye)
	# Retired, not freed. Rebuilds are metered at a few a frame, so dropping a
	# chunk the instant it falls out of the wanted set left a hole in the ground
	# for however many frames it took to get to its replacement -- terrain
	# visibly reloading in front of you. The old one stays up until the new one
	# is standing.
	var drop: Array = []
	for k in _live:
		if not want.has(k):
			drop.append(k)
	for k in drop:
		var n: Node = _live[k]
		if is_instance_valid(n):
			# Hand the name back before the replacement asks for it. Godot does
			# not uniquify a colliding child name -- it throws the requested one
			# away and assigns `@MeshInstance3D@507` instead -- so a chunk
			# rebuilt while its predecessor was still standing lost its identity
			# entirely, and every harness that finds leaves by name went blind
			# to it.
			n.name = "X%d" % n.get_instance_id()
			_retire[_base_key(k)] = n
			_retire_key[_base_key(k)] = k
		_live.erase(k)
	# keep anything already queued that is still wanted
	var keep: Array = []
	for job in _pending:
		if want.has(job[0]) and not _live.has(job[0]):
			keep.append(job)
	_pending = keep
	var queued: Dictionary = {}
	for job2 in _pending:
		queued[job2[0]] = true
	# and whatever is out with the pool right now, or it gets queued a second
	# time and the second commit orphans the first chunk in the tree
	for job3 in _batch:
		queued[job3[0]] = true
	for k2 in want:
		if queued.has(k2) or _live.has(k2):
			continue
		# Built once already and only hidden: take it straight back.
		var kept := _revive(k2)
		if kept != null:
			_live[k2] = kept
			# The one it supersedes steps down *now*. Coming off the shelf is
			# not a build, so nothing was ever queued for this key and
			# `_collect` -- which is where a replaced chunk was being hidden --
			# never ran. The predecessor stayed up, visible, drawing the same
			# ground at a different detail: two surfaces fighting for the same
			# pixels, which is exactly what the flickering was.
			var b3 := _base_key(k2)
			if _retire.has(b3):
				_stash(b3)
			continue
		_pending.append([k2, want[k2]])
	# nearest first: the ground you are about to fly over matters more than the
	# ground on the horizon, and a metered queue makes the order visible
	_pending.sort_custom(func(p: Array, q: Array) -> bool:
		return _job_dist(p[1], eye) < _job_dist(q[1], eye))
	_centre = eye
	if immediate:
		flush_pending()

## Nothing may outlive the node the workers are calling back into. Godot frees
## the tree while a batch is still in the pool otherwise, and the tasks land on
## a freed object -- "Nonexistent function '_tint' in base 'previously freed'".
func _exit_tree() -> void:
	if _batch_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_batch_id)
		_batch_id = -1
		_batch = []
		_batch_out = []

func _job_dist(a: Array, eye: Vector3) -> float:
	var span := span_at(int(a[0]))
	var cx := (float(int(a[1])) + 0.5) * span
	var cz := (float(int(a[2])) + 0.5) * span
	return Vector2(cx - eye.x, cz - eye.z).length_squared()

## Build queued chunks.
##
## The work of a chunk is 289 height samples, 1920 biome colours and the vertex
## assembly, and none of it touches the scene tree -- so it goes to the worker
## pool a batch at a time and comes back as plain arrays. Only turning those
## arrays into a mesh and hanging it in the tree happens here. At load that is
## the difference between a three second freeze and a progress bar that moves;
## in flight it is why crossing a detail boundary at five hundred knots does not
## drop a frame.
##
## With a budget, the batch is dispatched and collected across frames and this
## never blocks. Without one -- at load, and in the harnesses -- it runs the
## queue to the end before returning, still on the pool.
func flush_pending(budget := -1) -> int:
	var made := _collect()
	if budget < 0:
		while not _pending.is_empty() or _batch_id != -1:
			_dispatch(_pending.size())
			if _batch_id != -1:
				WorkerThreadPool.wait_for_group_task_completion(_batch_id)
				_batch_done = true
			made += _collect()
		stats["chunks"] = _live.size()
		return made
	if _batch_id == -1:
		_dispatch(budget)
	stats["chunks"] = _live.size()
	return made

## Hand the next few jobs to the pool. One task per chunk, each writing only its
## own slot of a pre-sized array.
func _dispatch(n: int) -> void:
	if _pending.is_empty() or n <= 0:
		return
	_batch = []
	for i in mini(n, _pending.size()):
		_batch.append(_pending.pop_front())
	_batch_out = []
	_batch_out.resize(_batch.size())
	_batch_done = false
	_batch_id = WorkerThreadPool.add_group_task(_build_one, _batch.size(), -1,
		false, "terrain chunks")

## Runs on a worker. Pure computation against the height and biome fields.
func _build_one(i: int) -> void:
	var a: Array = (_batch[i] as Array)[1]
	_batch_out[i] = _chunk_arrays(int(a[0]), int(a[1]), int(a[2]), a[3], int(a[4]))

## Take whatever the pool has finished and hang it in the tree.
func _collect() -> int:
	var made := 0
	if _batch_id != -1 and (_batch_done
			or WorkerThreadPool.is_group_task_completed(_batch_id)):
		made = _take_batch()
	# Anything still standing in for a chunk that is never coming -- the queue
	# is empty and nothing is out with the pool -- has gone out of view rather
	# than been replaced, so it can step down. This used to sit behind the early
	# return above and only ran on a frame that happened to finish a batch.
	if _pending.is_empty() and _batch_id == -1 and not _retire.is_empty():
		for b2 in _retire.keys():
			_stash(b2)
	return made

func _take_batch() -> int:
	WorkerThreadPool.wait_for_group_task_completion(_batch_id)
	_batch_id = -1
	_batch_done = false
	var made := 0
	for i in _batch.size():
		var key: String = (_batch[i] as Array)[0]
		var mi := _commit(_batch[i], _batch_out[i])
		if mi != null:
			_live[key] = mi
			# the one it replaces steps down now, and not before
			var b := _base_key(key)
			if _retire.has(b):
				_stash(b)
		made += 1
	_batch = []
	_batch_out = []
	return made

## Put a retired chunk away hidden, and throw out the oldest if the shelf is
## full. Freeing is the last resort, not the first.
func _stash(base: String) -> void:
	var n: Node = _retire.get(base)
	var k: String = String(_retire_key.get(base, ""))
	_retire.erase(base)
	_retire_key.erase(base)
	if not is_instance_valid(n):
		return
	if k == "" or _cache.has(k):
		n.queue_free()
		return
	(n as MeshInstance3D).visible = false
	_cache[k] = n
	_cache_age.append(k)
	while _cache_age.size() > CACHE_MAX:
		var old_k: String = _cache_age.pop_front()
		var old_n: Node = _cache.get(old_k)
		_cache.erase(old_k)
		if is_instance_valid(old_n):
			old_n.queue_free()

## Take a chunk back off the shelf, named and visible again, or null.
func _revive(k: String) -> MeshInstance3D:
	if not _cache.has(k):
		return null
	var mi: Node = _cache[k]
	_cache.erase(k)
	_cache_age.erase(k)
	if not is_instance_valid(mi):
		return null
	var bits := k.split(":")
	(mi as MeshInstance3D).name = "C%s_%s_%s" % [bits[0], bits[1], bits[2]]
	(mi as MeshInstance3D).visible = true
	return mi as MeshInstance3D

func _commit(job: Array, built: Variant) -> MeshInstance3D:
	if built == null:
		return null
	var out: Array = built
	var a: Array = job[1]
	var depth: int = int(a[0])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out[0]
	arr[Mesh.ARRAY_NORMAL] = out[1]
	arr[Mesh.ARRAY_COLOR] = out[2]
	arr[Mesh.ARRAY_TEX_UV2] = out[4]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, _mat)
	# Depth and index, which are the node's real name and unique by
	# construction. The rings used to name chunks by their metre coordinates,
	# and once two of them could want the same corner Godot quietly renamed the
	# second one out from under the harness that was counting them.
	var mi := MeshKit.mi(am, "C%d_%d_%d" % [depth, int(a[1]), int(a[2])])
	if debug_count:
		var bk := "%d:%d:%d" % [depth, int(a[1]), int(a[2])]
		debug_builds[bk] = int(debug_builds.get(bk, 0)) + 1
	# Only the two finest levels -- a 960 m leaf and smaller. A shadow map
	# spends its resolution on whatever is in it, and a node the size of a
	# county in there costs every close shadow its definition.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if depth >= MAX_DEPTH - 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	stats["seam"] = maxf(float(stats.get("seam", 0.0)), float(out[3]))
	stats["tris"] += CELLS * CELLS * 2
	return mi

func pending_count() -> int:
	return _pending.size() + _batch.size()

## Everything a chunk is, as plain arrays: vertices, normals, colours, and the
## seam the stitching left. Called on a worker thread, so it may read the height
## and biome fields and nothing else.
func _chunk_arrays(depth: int, ix: int, iz: int, nb: Array, fine: int) -> Array:
	var span := span_at(depth)
	var cell := span / float(CELLS)
	var x0 := float(ix) * span
	var z0 := float(iz) * span
	var n := CELLS + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	for j in n:
		for i in n:
			h[j * n + i] = Sim.height_at(x0 + i * cell, z0 + j * cell)
	_stitch(h, n, x0, z0, cell, depth, nb)
	# What the level above this one draws at each of our grid points. Even
	# indices sit on the parent's grid, so they read the same height and their
	# difference is zero; the odd ones in between are where the two surfaces
	# part company, and that difference is what gets morphed away. Computed from
	# the grid we already have -- the parent's vertices are our even ones -- so
	# it costs no height samples at all.
	var hc := PackedFloat32Array()
	hc.resize(n * n)
	for j in n:
		var pj: int = mini(j >> 1, HALF_CELLS - 1)
		var tz: float = (float(j) - float(pj * 2)) * 0.5
		for i in n:
			var pi: int = mini(i >> 1, HALF_CELLS - 1)
			var tx: float = (float(i) - float(pi * 2)) * 0.5
			var a0 := 2 * pi
			var b0 := 2 * pj
			var h00: float = h[b0 * n + a0]
			var h10: float = h[b0 * n + a0 + 2]
			var h11: float = h[(b0 + 2) * n + a0 + 2]
			var h01: float = h[(b0 + 2) * n + a0]
			# the same diagonal the chunks are triangulated on
			hc[j * n + i] = (h00 + (h10 - h00) * tx + (h11 - h10) * tz) if tz <= tx \
				else (h00 + (h11 - h01) * tx + (h01 - h00) * tz)
	# Pin the edges a finer neighbour has conformed itself to.
	for e in 4:
		if (fine & (1 << e)) == 0:
			continue
		for t in n:
			var at: int = t * n if e == 0 else (t * n + n - 1 if e == 1
				else (t if e == 2 else (n - 1) * n + t))
			hc[at] = h[at]
	var count := CELLS * CELLS * 6 + CELLS * 24
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var cols := PackedColorArray()
	var morph := PackedVector2Array()
	verts.resize(count)
	nrms.resize(count)
	cols.resize(count)
	morph.resize(count)
	var w := [0]
	for j in CELLS:
		for i in CELLS:
			var a := Vector3(x0 + i * cell, h[j * n + i], z0 + j * cell)
			var b := Vector3(x0 + (i + 1) * cell, h[j * n + i + 1], z0 + j * cell)
			var c := Vector3(x0 + (i + 1) * cell, h[(j + 1) * n + i + 1], z0 + (j + 1) * cell)
			var d := Vector3(x0 + i * cell, h[(j + 1) * n + i], z0 + (j + 1) * cell)
			var ma := hc[j * n + i] - h[j * n + i]
			var mb := hc[j * n + i + 1] - h[j * n + i + 1]
			var mc := hc[(j + 1) * n + i + 1] - h[(j + 1) * n + i + 1]
			var md := hc[(j + 1) * n + i] - h[(j + 1) * n + i]
			_face(verts, nrms, cols, morph, w, a, b, c, ma, mb, mc)
			_face(verts, nrms, cols, morph, w, a, c, d, ma, mc, md)
	_skirt(verts, nrms, cols, morph, w, x0, z0, cell, h, n)
	# every vertex carries how wide its chunk is, which is the band it blends over
	for mv in count:
		morph[mv] = Vector2(morph[mv].x, span)
	return [verts, nrms, cols,
		_conform_residual(h, n, x0, z0, cell, depth, nb), morph]

## A leaf's identity without its neighbour state, so a rebuild triggered only by
## a change next door can be matched to the chunk it supersedes.
func _base_key(k: String) -> String:
	var bits := k.split(":")
	return "%s:%s:%s" % [bits[0], bits[1], bits[2]] if bits.size() >= 4 else k

## What the stitching left behind: how far each conformed edge vertex still sits
## off the straight line its coarse neighbour draws through that span. Zero by
## construction if `_stitch` did its job, and the number the seam harnesses gate
## on -- so it is measured rather than assumed.
func _conform_residual(h: PackedFloat32Array, n: int, x0: float, z0: float,
		cell: float, depth: int, nb: Array) -> float:
	var span := cell * float(CELLS)
	var worst := 0.0
	for side in 4:
		var nd: int = int(nb[side])
		if nd >= depth:
			continue
		var big := span_at(nd) / float(CELLS)
		for i in range(1, n - 1):
			var t: float = float(i) * cell
			var got: float
			var want: float
			if side == 0:
				got = h[i * n]
				want = _coarse_at(x0, z0 + t, big, false)
			elif side == 1:
				got = h[i * n + n - 1]
				want = _coarse_at(x0 + span, z0 + t, big, false)
			elif side == 2:
				got = h[i]
				want = _coarse_at(x0 + t, z0, big, true)
			else:
				got = h[(n - 1) * n + i]
				want = _coarse_at(x0 + t, z0 + span, big, true)
			worst = maxf(worst, absf(got - want))
	return worst

## The height the coarser ring draws at a point on the shared edge: its two
## nearest vertices on that edge, linearly interpolated, which is what its
## triangles do between them.
func _coarse_at(x: float, z: float, big: float, along_x: bool) -> float:
	if along_x:
		var lo: float = floor(x / big) * big
		var f: float = (x - lo) / big
		return lerpf(Sim.height_at(lo, z), Sim.height_at(lo + big, z), f)
	var lo2: float = floor(z / big) * big
	var f2: float = (z - lo2) / big
	return lerpf(Sim.height_at(x, lo2), Sim.height_at(x, lo2 + big), f2)

## Stitch the edges that face a coarser neighbour.
##
## A coarser node has cells twice as wide (or four times, or eight), so along a
## shared boundary it has a vertex only at every second, fourth, eighth one of
## ours. Its edge runs straight past the rest of ours, and wherever the ground
## is not flat the two surfaces part company: measured across this map, ten
## metres on average and two hundred and fifty at worst. Skirts were hiding
## that rather than fixing it. Reading the height the coarse neighbour would
## read puts our edge exactly on its edge, and the gap becomes zero by
## construction rather than by being covered up.
##
## Only the coarse side of a boundary is deferred to, so exactly one of the two
## chunks moves and they cannot both chase each other.
func _stitch(h: PackedFloat32Array, n: int, x0: float, z0: float,
		cell: float, depth: int, nb: Array) -> void:
	var span := cell * float(CELLS)
	for side in 4:
		var nd: int = int(nb[side])
		if nd >= depth:
			continue
		# the neighbour's cell, which its edge is straight across
		var big := span_at(nd) / float(CELLS)
		for i in range(1, n - 1):
			var t: float = float(i) * cell
			if side == 0:
				h[i * n] = _coarse_at(x0, z0 + t, big, false)
			elif side == 1:
				h[i * n + n - 1] = _coarse_at(x0 + span, z0 + t, big, false)
			elif side == 2:
				h[i] = _coarse_at(x0 + t, z0, big, true)
			else:
				h[(n - 1) * n + i] = _coarse_at(x0 + t, z0 + span, big, true)
	# The corners belong to both edges at once. A corner that is an endpoint of
	# a coarse span on one axis has to sit on that span, and since the two
	# meeting edges share it, doing them in sequence would let the second undo
	# the first. They are left on the raw field: every node's grid is a whole
	# number of BASE_CELL steps from the origin, so a coarse neighbour has a
	# vertex at our corner whatever its depth, and both read the same height.

## A vertical curtain around the chunk edge so a coarser neighbour cannot show
## daylight through the seam.
func _skirt(verts: PackedVector3Array, nrms: PackedVector3Array,
		cols: PackedColorArray, morph: PackedVector2Array, w: Array,
		x0: float, z0: float, cell: float,
		h: PackedFloat32Array, n: int) -> void:
	# Clamped, and hard. This was `cell * 3`, which on the coarsest leaves is a
	# cell size of kilometres and therefore a curtain hanging kilometres under
	# every chunk -- visible from anywhere at or below sea level, which is
	# exactly where a submarine is. The skirt only has to cover the crack where
	# two levels meet, and the boundary stitching already pulls that to a
	# fraction of a millimetre, so a few centimetres is ample.
	var drop: float = clampf(cell * 0.004, 0.15, 0.6)
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
				var k: int = w[0]
				verts[k] = v
				nrms[k] = Vector3.UP
				cols[k] = col
				# the curtain hangs from the edge, which is conformed and so
				# never morphs; giving it a morph of its own would peel it away
				morph[k] = Vector2.ZERO
				w[0] = k + 1

func _face(verts: PackedVector3Array, nrms: PackedVector3Array,
		cols: PackedColorArray, morph: PackedVector2Array, w: Array,
		a: Vector3, b: Vector3, c: Vector3,
		ma: float, mb: float, mc: float) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var vs := [a, b, c]
	var ms := [ma, mb, mc]
	for i in 3:
		var k: int = w[0]
		verts[k] = vs[i]
		nrms[k] = nrm
		cols[k] = _tint(vs[i], nrm.y)
		morph[k] = Vector2(ms[i], 0.0)
		w[0] = k + 1

func _tint(v: Vector3, slope: float) -> Color:
	# Biome only. Roads and made ground are in the ground mask, sampled per
	# fragment, because a vertex can only be as sharp as its cell.
	var c := Sim.biome_colour(v.x, v.z, v.y, slope)
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

## The height of the ground as it is actually *drawn* at a point.
##
## Anything standing on the ground has to be placed on this rather than on the
## raw field, or it stands above the drawn surface with daylight under it: from
## above that reads as a slight sink, from below as a wood floating in mid-air.
##
## Read at the finest detail the tree can reach, because that is what the ground
## is drawn at whenever the eye is near enough for the difference to be visible.
## Further out the leaves are coarser and this is an approximation -- but the
## error test that chose those leaves is exactly the measure of how coarse an
## approximation, and it only lets them be coarse where the surface barely moves.
static func surface_height(x: float, z: float) -> float:
	var cell := BASE_CELL
	var x0: float = floor(x / cell) * cell
	var z0: float = floor(z / cell) * cell
	var tx: float = (x - x0) / cell
	var tz: float = (z - z0) / cell
	var h00 := Sim.height_at(x0, z0)
	var h10 := Sim.height_at(x0 + cell, z0)
	var h11 := Sim.height_at(x0 + cell, z0 + cell)
	var h01 := Sim.height_at(x0, z0 + cell)
	# the chunk splits each cell as (a,b,c) then (a,c,d): a=(0,0) b=(1,0)
	# c=(1,1) d=(0,1), so the diagonal runs from (0,0) to (1,1)
	if tz <= tx:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz

## The cell size the ground can be drawn at here. Anything that needs the mesh
## to be able to *represent* a feature has to know how big a triangle is: a two
## kilometre runway cannot be flattened into a grid whose cells are four
## kilometres across, however carefully the height field is levelled.
##
## One number now, where the rings made it a function of distance from the
## airfield at the world origin. That was never really about the terrain -- it
## was about the rings being nailed there, so a second airfield four hundred
## kilometres away was told its runway had to be four kilometres wide to show up.
## Under the quadtree any point reaches BASE_CELL once you are standing on it,
## so every field is levelled to the same tolerance as the home one. It also
## takes a ring walk out of `Sim.height_at`, which is the hottest call in the
## map bake.
static func cell_at(_x: float, _z: float) -> float:
	return BASE_CELL
