class_name Terrain
extends Node3D
## Modular chunked terrain. The map is covered by concentric rings of square
## chunks; every ring uses a coarser cell size than the one inside it. All of
## them sample the same analytic height and biome fields, so neighbouring
## chunks line up exactly and the biome bands run continuously across chunk
## borders. Vertical skirts hide the T-junctions where two rings meet.

const CELLS := 16                     # cells per chunk edge, every ring
## Innermost cell size. This is the finest detail the ground can hold, and it is
## also the finest anything *painted into* the ground can hold — a road stain
## narrower than a cell has no vertices to land on and flickers with the grid.
## Halved from 30 m, with a level added so the outermost ring still reaches the
## same distance: 15 x 2^7 is the same 1920 m cell the old outer ring used.
const BASE_CELL := 15.0
const OUT := 4                        # chunks from the middle to the edge of a ring
## Each level doubles the cell size and reaches four chunks out, so every level
## added doubles the world's radius for a fixed forty-eight chunks — the rings
## are the whole point of the scheme. Eight levels reached 92 km; twelve reach
## almost fifteen hundred, for about two hundred more chunks.
const LEVELS := 12

## Every ring doubles the cell size and reaches OUT chunks out, so the hole in
## the middle of a ring is exactly two of that ring's chunks and the finer ring
## inside fills it precisely. Getting this wrong leaves coarse chunks lying over
## fine ones, which is what tore holes in the mountains.
## Built once. This allocated twelve dictionaries every time it was asked, and
## `cell_at` asks on every height query, once per airfield — about nineteen
## million allocations to bake the map, which took twelve seconds.
static var _rings: Array = []

static func ring_table() -> Array:
	if not _rings.is_empty():
		return _rings
	_rings = _build_rings()
	return _rings

static func _build_rings() -> Array:
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
uniform vec3 tarmac : source_color = vec3(0.135, 0.133, 0.140);
uniform vec3 made_ground : source_color = vec3(0.335, 0.325, 0.305);

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
	vec2 muv = wpos.xz / (mask_half * 2.0) + vec2(0.5);
	float road_amt = 0.0;
	float town_amt = 0.0;
	if (muv.x > 0.0 && muv.x < 1.0 && muv.y > 0.0 && muv.y < 1.0) {
		vec2 mk = texture(ground_mask, muv).rg;
		road_amt = mk.r;
		town_amt = mk.g;
	}
	float grit = (grain - 0.5) * 0.09;
	base = mix(base, pow(made_ground, vec3(2.2)) * (1.0 + grit), town_amt * 0.85);
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
func _bake_ground_mask() -> ImageTexture:
	var n := MASK_N
	var t0 := Time.get_ticks_msec()
	var buf := PackedByteArray()
	buf.resize(n * n * 2)
	var tpm: float = float(n) / (MASK_HALF * 2.0)     # texels per metre
	# made ground under the settlements
	for pad in Sim._town_pads:
		var pc: Vector2 = pad["c"]
		var pr: float = pad["r"]
		_stamp_disc(buf, n, tpm, pc, pr * 1.02, pr * 1.32, 1)
	# then the network: trunk roads wide, streets narrow
	for r in Sim.ROADS:
		_stamp_capsule(buf, n, tpm, r[0], r[1], 9.0, 30.0, 0)
	for r in Sim._segments:
		_stamp_capsule(buf, n, tpm, r[0], r[1], 5.0, 13.0, 0)
	var road_px := 0
	var town_px := 0
	for k in range(0, buf.size(), 2):
		if buf[k] > 96:
			road_px += 1
		if buf[k + 1] > 96:
			town_px += 1
	stats["mask_ms"] = Time.get_ticks_msec() - t0
	stats["mask_road_px"] = road_px
	stats["mask_town_px"] = town_px
	stats["mask_m_per_texel"] = snappedf(1.0 / tpm, 0.01)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RG8, buf)
	# A second 33 MB copy is only worth carrying when something is going to
	# measure it; in a normal session the GPU has the only copy it needs.
	if OS.has_feature("headless") or OS.is_debug_build():
		mask_img = img.duplicate()      # un-mipmapped, for the harness
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## What the ground actually shows at a world point: red tarmac, green made
## ground, straight out of the baked mask.
func mask_at(x: float, z: float) -> Vector2:
	if mask_img == null:
		return Vector2.ZERO
	var tpm: float = float(MASK_N) / (MASK_HALF * 2.0)
	var i := clampi(int((x + MASK_HALF) * tpm), 0, MASK_N - 1)
	var j := clampi(int((z + MASK_HALF) * tpm), 0, MASK_N - 1)
	var c := mask_img.get_pixel(i, j)
	return Vector2(c.r, c.g)

## World metres to texel, clamped to the image.
func _to_texel(tpm: float, n: int, v: float) -> int:
	return clampi(int((v + MASK_HALF) * tpm), 0, n - 1)

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

## Live chunks, keyed by level and grid position. The rings used to be laid out
## once around the world origin, which is the airfield — so the ground was
## detailed there and coarse everywhere else, however far you flew. They follow
## the viewer now.
var _live: Dictionary = {}
var _centre := Vector3(1e12, 0.0, 1e12)
var _pending: Array = []
var _retire: Dictionary = {}

func build() -> void:
	_mat = _ground_material()
	recentre(Vector3.ZERO, true)
	_water()

## Where each ring's grid sits for a given eye position. Snapped to *twice* its
## own cell size, which is the whole trick: ring L+1's span is two of ring L's,
## so snapping both to the coarser grid makes their chunk boundaries land on
## each other by construction. Snap each ring to its own span instead and the
## holes drift apart into overlaps and cracks.
func _ring_origin(eye: Vector3, span: float) -> Vector2:
	var q := span * 2.0
	return Vector2(round(eye.x / q) * q, round(eye.z / q) * q)

## The set of chunks that should exist for this eye position.
func _wanted(eye: Vector3) -> Dictionary:
	var out: Dictionary = {}
	var tbl := ring_table()
	var inner_lo := Vector2.ZERO
	var inner_hi := Vector2.ZERO
	var have_inner := false
	for lvl in tbl.size():
		var r: Dictionary = tbl[lvl]
		var cell: float = float(r["cell"])
		var span: float = cell * float(CELLS)
		var n: int = int(r["n"])
		var o := _ring_origin(eye, span)
		var lo := Vector2(o.x - float(n) * span, o.y - float(n) * span)
		var hi := Vector2(o.x + float(n) * span, o.y + float(n) * span)
		for cz in range(-n, n):
			for cx in range(-n, n):
				var x0: float = o.x + float(cx) * span
				var z0: float = o.y + float(cz) * span
				# Skip anything the finer ring already covers. Measured against
				# that ring's *actual* extent, not a constant taken from the
				# world origin — which is what stopped any of this moving.
				if have_inner and x0 >= inner_lo.x and x0 + span <= inner_hi.x \
						and z0 >= inner_lo.y and z0 + span <= inner_hi.y:
					continue
				# The key carries which edges face the coarser ring outside
				# this one. A chunk keeps its grid index when the clipmap
				# moves, so without this it was kept as-is — with the edge
				# stitching it was built with, for a ring centred somewhere
				# else. Interior chunks still survive a move untouched; only
				# the ones whose boundary status changed get rebuilt.
				var eg := 0
				if absf(x0 - lo.x) < cell * 0.01:
					eg |= 1
				if absf(x0 + span - hi.x) < cell * 0.01:
					eg |= 2
				if absf(z0 - lo.y) < cell * 0.01:
					eg |= 4
				if absf(z0 + span - hi.y) < cell * 0.01:
					eg |= 8
				out["%d:%d:%d:%d" % [lvl, int(round(x0 / span)),
					int(round(z0 / span)), eg]] = \
					[x0, z0, cell, bool(r["shadow"]), span * float(n), o]
		inner_lo = lo
		inner_hi = hi
		have_inner = true
	return out

## Move the clipmap. Cheap when nothing has changed: the wanted set is compared
## against what is live and only the difference is touched.
func recentre(eye: Vector3, immediate := false) -> void:
	# Nothing to do until the eye has moved far enough to change a ring's
	# snapped origin, which is most frames. Recomputing the wanted set every
	# frame would cost more than the rebuilds it saves.
	if not immediate and _centre.distance_squared_to(eye) < 90000.0:
		return
	var want := _wanted(eye)
	# Retired, not freed. Rebuilds are metered at a few a frame, so dropping a
	# chunk the instant it falls out of the wanted set left a hole in the ground
	# for however many frames it took to get to its replacement — terrain
	# visibly reloading in front of you. The old one stays up until the new one
	# is standing.
	var drop: Array = []
	for k in _live:
		if not want.has(k):
			drop.append(k)
	for k in drop:
		var n: Node = _live[k]
		if is_instance_valid(n):
			_retire[_base_key(k)] = n
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
	for k in want:
		if queued.has(k):
			continue
		if not _live.has(k):
			_pending.append([k, want[k]])
	_centre = eye
	if immediate:
		flush_pending()

## Build queued chunks. Called with a budget from the world so a long flight
## does not stall on a ring boundary; called without one at load.
func flush_pending(budget := -1) -> int:
	var made := 0
	while not _pending.is_empty() and (budget < 0 or made < budget):
		var job: Array = _pending.pop_front()
		var a: Array = job[1]
		var mi := _chunk(a[0], a[1], a[2], a[3], a[4], a[5])
		if mi != null:
			_live[job[0]] = mi
			# the one it replaces can go now, and not before
			var b := _base_key(job[0])
			if _retire.has(b):
				var old_n: Node = _retire[b]
				if is_instance_valid(old_n):
					old_n.queue_free()
				_retire.erase(b)
		made += 1
	if _pending.is_empty() and not _retire.is_empty():
		# whatever is left really has gone off the map
		for b2 in _retire:
			var n2: Node = _retire[b2]
			if is_instance_valid(n2):
				n2.queue_free()
		_retire.clear()
	return made

## A chunk's identity without its edge state, so a rebuild triggered only by a
## change of neighbours can be matched to the chunk it supersedes.
func _base_key(k: String) -> String:
	var bits := k.split(":")
	return "%s:%s:%s" % [bits[0], bits[1], bits[2]] if bits.size() >= 3 else k

func pending_count() -> int:
	return _pending.size()

func _chunk(x0: float, z0: float, cell: float, shadow: bool, coverage: float,
		ring_o := Vector2.ZERO) -> MeshInstance3D:
	var n := CELLS + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	for j in n:
		for i in n:
			h[j * n + i] = Sim.height_at(x0 + i * cell, z0 + j * cell)
	_stitch(h, n, x0, z0, cell, coverage, ring_o)
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
	var mi := MeshKit.mi(MeshKit.finish(st, _mat), # the level too: rings share snapped origins now, so two of them can want
	# the same x0 and z0 and Godot quietly renames the second one
	"C%d_%d_%d" % [int(cell), int(x0), int(z0)])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var resid := 0.0
	if absf(z0 - (ring_o.y - coverage)) < cell * 0.01:
		for i in range(1, n - 1, 2):
			resid = maxf(resid, absf(h[i] - (h[i - 1] + h[i + 1]) * 0.5))
	if absf(x0 - (ring_o.x - coverage)) < cell * 0.01:
		for j in range(1, n - 1, 2):
			resid = maxf(resid, absf(h[j * n] - (h[(j - 1) * n] + h[(j + 1) * n]) * 0.5))
	stats["seam"] = maxf(float(stats.get("seam", 0.0)), resid)
	stats["chunks"] = _live.size() + 1
	stats["tris"] += CELLS * CELLS * 2
	return mi

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
		cell: float, coverage: float, ring_o := Vector2.ZERO) -> void:
	var span := cell * float(CELLS)
	var eps := cell * 0.01
	# Which edges face the coarser ring outside this one. These used to be
	# measured from the world origin, because that is where the rings were
	# nailed down; now the ring has a centre of its own and they are measured
	# from that.
	var wx := ring_o.x - coverage
	var ex := ring_o.x + coverage
	var wz := ring_o.y - coverage
	var ez := ring_o.y + coverage
	# Resampled on the coarse grid, not averaged between neighbours. Averaging
	# assumes the fine chunk's even vertices land exactly on the coarse ring's
	# vertices — true when both rings were nailed to the world origin, and no
	# longer true now each ring snaps to its own centre. Reading the height the
	# coarse ring would read makes the edge conform whatever the offsets are.
	var big := cell * 2.0
	# west and east columns
	if absf(x0 - wx) < eps:
		for j in range(1, n - 1):
			h[j * n] = _coarse_at(x0, z0 + float(j) * cell, big, false)
	if absf(x0 + span - ex) < eps:
		for j in range(1, n - 1):
			h[j * n + n - 1] = _coarse_at(x0 + span, z0 + float(j) * cell, big, false)
	# north and south rows
	if absf(z0 - wz) < eps:
		for i in range(1, n - 1):
			h[i] = _coarse_at(x0 + float(i) * cell, z0, big, true)
	if absf(z0 + span - ez) < eps:
		for i in range(1, n - 1):
			h[(n - 1) * n + i] = _coarse_at(x0 + float(i) * cell, z0 + span, big, true)

## A vertical curtain around the chunk edge so a coarser neighbour cannot show
## daylight through the seam.
func _skirt(st: SurfaceTool, x0: float, z0: float, cell: float, h: PackedFloat32Array, n: int) -> void:
	# Clamped, and hard. This was `cell * 3`, which on the outermost ring is a
	# cell size of 1920 m and therefore a **five and a half kilometre** curtain
	# hanging under every chunk — visible from anywhere at or below sea level,
	# which is exactly where a submarine is. The skirt only has to cover the
	# crack where two rings meet, and the boundary stitching already pulls that
	# to a fraction of a millimetre, so a few metres is ample.
	# Measured, not guessed. The stitching leaves a seam of 0.000061 m, so the
	# curtain only ever had to be a hair deep; at `cell * 0.35` it hung twelve
	# metres under every chunk edge and nine on average, and under water that
	# curtain is the only thing down there to look at. Sixty centimetres is
	# still four orders of magnitude more than the crack it covers.
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

## The height of the ground as it is actually *drawn* at a point, which is not
## the same as the analytic height the field returns. Each chunk is a grid of
## flat triangles, and on the outer rings a cell is nearly two kilometres
## across — so the surface you can see can sit tens of metres away from
## `Sim.height_at`. Anything placed on the ground has to be placed on this one,
## or it stands above the drawn surface with daylight under it. From above that
## reads as a slight sink; from below, looking up at the underside, it reads as
## a wood floating in mid-air.
static func surface_height(x: float, z: float) -> float:
	var tbl := ring_table()
	var cell: float = BASE_CELL
	var reach: float = maxf(absf(x), absf(z))
	for lvl in tbl:
		cell = float(lvl["cell"])
		if reach <= float(lvl["coverage"]):
			break
	# corners of the cell this point falls in
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

## The cell size the ground is drawn at here. Anything that needs the mesh to
## be able to *represent* a feature has to know how big a triangle is: a two
## kilometre runway cannot be flattened into a grid whose cells are four
## kilometres across, however carefully the height field is levelled.
static func cell_at(x: float, z: float) -> float:
	# Straight from the ring geometry rather than by walking a table: each ring
	# doubles the cell and reaches OUT chunks, so which one covers a point is
	# arithmetic.
	var reach: float = maxf(absf(x), absf(z))
	var cell: float = BASE_CELL
	var cover: float = BASE_CELL * float(CELLS) * float(OUT)
	for i in LEVELS - 1:
		if reach <= cover:
			return cell
		cell *= 2.0
		cover *= 2.0
	return cell
