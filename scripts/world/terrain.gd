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

## How much less a node that is entirely under water is worth subdividing. The
## error metric measures the seabed as faithfully as it measures a mountain
## range, and spent the same triangles on it -- for relief that is under a
## couple of hundred metres of water and, from a submarine, in the dark.
##
## Read by the extension, which is where the tree is walked; here so that the
## rule is written down once, next to the other constants that shape it.
const SEABED_DETAIL := 0.12

## Every ground material, so the season can be pushed to all of them. The
## chunks are built as the tree splits, so there is no single material to hold.
var _ground_mats: Array = []

static func span_at(depth: int) -> float:
	return ROOT_SPAN / float(1 << depth)

## The highest ground in a node, measured if nobody has asked yet.
static func node_top(depth: int, ix: int, iz: int) -> float:
	return Sim.native.terrain_node_top(depth, ix, iz)

## A node that is already subdivided has to be got clearly further away before
## it merges again, and one that is not has to be got clearly closer before it
## splits.
##
## One, now: no hysteresis at all.
##
## It was added to stop the tree re-deciding on the same threshold and churning,
## and it did. But it is fundamentally at odds with the blend. A node hands over
## to its children at SPLIT_K spans, which is exactly where the children's blend
## reads 1 and they are shaped like it -- seamless. Take it back at 1.45 times
## that and the coarser chunk reappears 45% of the way through its *own* blend,
## partly morphed toward its parent, while the children it replaced were fully
## morphed to its unmorphed shape. That mismatch is a pop every time you fly
## away from something. Splitting and merging on the same distance makes both
## directions exact, and the shelf of built chunks -- which is what actually
## fixed the churn -- absorbs the crossing for nothing.
const HYST := 1.0
## Asking for chunks before they are needed was tried and made it worse.
##
## A chunk hands over invisibly only if it appears at the far end of its own
## blend, still drawn in its parent's shape, and 86 of 1222 were arriving half
## unfolded. The obvious fix is to order them sooner -- but the wanted set grows
## with the cube of the radius, so asking a quarter early put 715 chunks in the
## world instead of 505 and the longer queue swallowed the head start whole:
## 191 of 1518 arrived mid-blend, more than twice as many. The limit is the
## queue's throughput, not when it is asked.

## A node's identity as one integer.
##
## This was a formatted string, and every split test built three of them -- one
## for the hysteresis set, one for the error table, one for the water table.
## Walking the tree touches about ninety thousand of those, and one look at the
## whole tree therefore cost 29 ms: a visible hitch every time the ground was
## reconsidered. Depth needs four bits and the index twenty-seven each, which
## fits an int with room to spare.
##
## The walk is in the extension now and keys its own tables the same way; this
## is what the harness checks it against.
static func _node_key(depth: int, ix: int, iz: int) -> int:
	return (depth << 54) | ((ix & 0x7FFFFFF) << 27) | (iz & 0x7FFFFFF)

var _mat: ShaderMaterial
var mask_img: Image = null
var stats := {"chunks": 0, "tris": 0, "seam": 0.0}

const GROUND_SHADER := """
shader_type spatial;
// Radius of the planet the ground is drawn as a piece of. Zero draws it flat.
uniform float curve_radius = 6371000.0;
// Drawn from underneath as well. Terrain faces up, so with back faces culled
// every triangle of the seabed is a back face when you are below it: from a
// submarine you looked straight through the ground at the sky.
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// How far out the fine grain is worth drawing. Beyond this the ground goes back
// to flat biome colour, which is all you can resolve anyway and costs nothing.
uniform float detail_fade = 1100.0;

// Crossfade against the planet body: 1 draws the ground, 0 leaves it to the
// sphere. Done by dropping pixels on an interleaved gradient rather than by
// turning the ground transparent -- the ground would then have to be sorted
// against itself, and a quadtree of chunks has no sort order worth the name.
// Dithered it stays opaque, keeps writing depth, and simply thins out.
uniform float ground_fade = 1.0;

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

// The climate field, baked once for the whole world: red is temperature noise,
// green is moisture, both already mapped to 0..1. The biome rule is otherwise
// closed-form arithmetic, so with these two numbers available per fragment the
// ground colour can be evaluated where it is drawn instead of at the corners of
// a cell.
uniform sampler2D climate : filter_linear;
uniform float world_half = 600000.0;
// The planet's frame, for working out where a fragment is on it.
uniform float round_world = 0.0;
uniform float planet_r = 6371000.0;
uniform float climate_squeeze = 7.5;
uniform float season = 0.0;
uniform float season_amp = 0.12;
uniform vec3 chart_origin = vec3(0.0, 1.0, 0.0);
uniform vec3 chart_east = vec3(1.0, 0.0, 0.0);
uniform vec3 chart_south = vec3(0.0, 0.0, 1.0);
uniform vec3 planet_north = vec3(0.0, 0.0, -1.0);
uniform float water_level = -35.0;

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

// The palette, and the biome rule itself, transcribed from Sim.biome_weights.
// It lives here as well as there because the two need to agree exactly: the
// scatter asks the CPU which biome a point is in to choose a species, and the
// ground under those trees is painted by this.
const vec3 C_SNOW   = vec3(0.93, 0.95, 0.98);
const vec3 C_ROCK   = vec3(0.31, 0.28, 0.26);
const vec3 C_FOREST = vec3(0.13, 0.24, 0.12);
const vec3 C_GRASS  = vec3(0.22, 0.33, 0.15);
const vec3 C_STEPPE = vec3(0.44, 0.41, 0.23);
const vec3 C_SAND   = vec3(0.60, 0.55, 0.38);
const vec3 C_MARSH  = vec3(0.19, 0.28, 0.20);

// `upness` is the normal's y: 1 is flat ground, 0 is a wall. `cl` is the
// climate sample. Returns the colour in sRGB, as the palette is authored.
vec3 biome_at(vec2 xz, float y_in, float upness, vec2 cl) {
	// Height above the sea under this point, not the world `y`.
	//
	// The two are the same on a flat world and are not on a planet: the ground
	// falls away from the middle of the chart, so a place's height -- and with
	// it its snow line, its treeline and its beaches -- depended on where the
	// chart happened to be centred. `Sim.biome_weights` makes the same
	// correction, and the two have to agree or the ground is not the colour the
	// game thinks it is.
	float y = y_in;
	if (round_world > 0.5) {
		float rr = length(xz);
		y += planet_r * (1.0 - cos(rr / planet_r));
	}
	// Where this is on the planet, not where it is on the chart. See
	// `Sim.climate_lat`: the flat world reads the pair's `z`, which makes a
	// place's climate depend on where the chart happens to be centred.
	float lat;
	if (round_world > 0.5) {
		float s = max(length(xz), 1.0);
		float ang = s / planet_r;
		vec3 d = chart_origin * cos(ang)
			+ (chart_east * (xz.x / s) + chart_south * (xz.y / s)) * sin(ang);
		lat = clamp(abs(dot(normalize(d), planet_north)) * climate_squeeze,
			0.0, 1.0);
	} else {
		lat = clamp(abs(xz.y) / (world_half * 0.85), 0.0, 1.0);
	}
	// What the season is worth here. Nothing at the equator, most at the poles,
	// and opposite signs either side of the line -- which is the difference
	// between one hemisphere having winter and both of them having it at once.
	// `slat` is the signed latitude; `lat` above is it folded.
	float warmth = 0.0;
	if (round_world > 0.5) {
		float s2 = max(length(xz), 1.0);
		float ang2 = s2 / planet_r;
		vec3 d2 = chart_origin * cos(ang2)
			+ (chart_east * (xz.x / s2) + chart_south * (xz.y / s2)) * sin(ang2);
		warmth = season * dot(normalize(d2), planet_north) * season_amp;
	}
	float band = 1.0 - lat * 1.25;
	float belt = clamp(1.0 - abs(lat - 0.32) * 3.0, 0.0, 1.0);
	float temp = clamp(band * 0.70 + cl.r * 0.42
		- clamp((y - 300.0) / 2200.0, 0.0, 1.0) * 0.85
		+ warmth, 0.0, 1.0);
	float moist = clamp(cl.g
		+ clamp(1.0 - abs(y - water_level) / 900.0, 0.0, 1.0) * 0.25
		- belt * 0.66, 0.0, 1.0);
	float steep = clamp((0.90 - upness) / 0.34, 0.0, 1.0);
	float w_snow = clamp((y - 1500.0) / 700.0, 0.0, 1.0) * (1.0 - steep * 0.7)
			* clamp(1.0 - temp * 1.4, 0.0, 1.0)
		+ clamp((y - 2400.0) / 500.0, 0.0, 1.0)
		+ clamp((0.18 - temp) / 0.18, 0.0, 1.0) * 1.6;
	float w_rock = steep + clamp((y - 1100.0) / 1400.0, 0.0, 1.0) * 0.5;
	float w_forest = clamp(moist * 1.5 - 0.35, 0.0, 1.0)
		* clamp(temp * 1.6, 0.0, 1.0)
		* clamp(1.0 - (y - 200.0) / 1500.0, 0.0, 1.0);
	float w_grass = clamp(1.0 - abs(moist - 0.55) * 3.2, 0.0, 1.0) * 0.85
		* clamp(1.0 - (y - 400.0) / 1600.0, 0.0, 1.0);
	float w_steppe = clamp(0.62 - moist, 0.0, 1.0) * 1.7
		* clamp(temp * 1.3, 0.0, 1.0);
	float w_sand = clamp(1.0 - abs(y - water_level) / 26.0, 0.0, 1.0) * 1.4
		+ clamp(0.40 - moist, 0.0, 1.0) * clamp(temp - 0.30, 0.0, 1.0) * 7.0;
	float w_marsh = clamp(moist - 0.72, 0.0, 1.0) * 2.2
		* clamp(1.0 - abs(y - water_level) / 140.0, 0.0, 1.0);
	float total = w_snow + w_rock + w_forest + w_grass + w_steppe
		+ w_sand + w_marsh;
	vec3 c = C_GRASS;
	if (total >= 0.001) {
		c = (C_SNOW * w_snow + C_ROCK * w_rock + C_FOREST * w_forest
			+ C_GRASS * w_grass + C_STEPPE * w_steppe + C_SAND * w_sand
			+ C_MARSH * w_marsh) / total;
	}
	// the seabed, which the biome field knows nothing about
	if (y < water_level) {
		float deep = clamp((water_level - y) / 150.0, 0.0, 1.0);
		vec3 bed = mix(vec3(0.46, 0.42, 0.33), vec3(0.17, 0.18, 0.19), deep);
		c = mix(c, bed, clamp((water_level - y) / 10.0, 0.0, 1.0));
	}
	return c;
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
	// In three dimensions, matching the test that decides which level draws
	// this chunk at all. Measured flat they disagree the moment you gain any
	// height, and the blend then no longer lines up with the hand-over.
	float m = clamp((distance(wp, CAMERA_POSITION_WORLD) - lo)
		/ max(hi - lo, 1.0), 0.0, 1.0);
	VERTEX.y += m * UV2.x;
	// ...and the normal goes with it. The vertex carries the normal of the
	// triangle it was built with; the morph then moves the vertex, so through a
	// hand-over the shading belonged to a shape the ground no longer had, and
	// slope-dependent rock came and went across whole hillsides. TANGENT holds
	// the normal the level above draws there, and the same blend takes one to
	// the other.
	//
	// Done here and not from screen-space derivatives in the fragment stage:
	// derivatives are computed per two-by-two pixel quad, so every quad
	// straddling a triangle edge gets a normal belonging to neither -- which
	// speckles the whole surface and is worse than the fault it fixed.
	NORMAL = normalize(mix(NORMAL, TANGENT, m));
	// Planet curvature, applied to the drawn surface only.
	//
	// The simulation is a height field on a plane and everything in it — every
	// road wheel's contact, every missile's ground test, the router, the
	// survey, the water plane — is written against that. What curvature does is
	// bend the ground AWAY from the viewer with distance, which is what a
	// planet looks like: the horizon drops, and something far off goes below it
	// feet first instead of shrinking to a dot on a flat plate.
	//
	// Falling away as d^2 / 2R is the exact sagitta of a sphere of radius R for
	// small angles, so with R set to the Earth's this is not an approximation of
	// the curve, it IS the curve — it is only the physics that stays flat.
	// About the WORLD ORIGIN, not the camera. Curving away from the viewer is
	// the cheap trick that keeps whoever is looking permanently on top of the
	// hill — it looks right and is a lie, and worse, it cannot agree with the
	// physics, because `Sim.height_at` has to answer the same question without
	// knowing where anyone is standing. Both now drop by exactly d^2/2R from
	// the same fixed point, so the ground you see and the ground you land on
	// are the same surface.
	if (curve_radius > 0.0) {
		vec3 wv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		VERTEX.y -= (wv.x * wv.x + wv.z * wv.z) / (2.0 * curve_radius);
	}
	// The colour needs no morph of its own any more. It used to be carried per
	// vertex and blended toward the parent level's colour through a hand-over;
	// now the fragment stage works it out from this position and this normal,
	// both of which are already morphed, so it follows them continuously and
	// there is nothing left to step.
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (ground_fade < 0.999) {
		float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy,
			vec2(0.06711056, 0.00583715))));
		if (ground_fade <= ign) {
			discard;
		}
	}
	// underside: the surface faces up, so light it with the normal turned round
	// rather than as though the sun were shining up through it
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 gn = wnrm;
	// The biome colour, worked out here rather than at the corners of the cell.
	// Baked per vertex it was interpolated across the two triangles a cell is
	// drawn as, and linear interpolation over a split quad is not bilinear: it
	// creases along the diagonal wherever the four corners are not coplanar in
	// colour, which is most of the time. Every cell in the world showed its own
	// triangulation. Evaluated against the fragment's own position it is a
	// continuous function of the ground and there is no diagonal to see -- and
	// because it reads the morphed height and the morphed normal, it also stays
	// continuous through a level change instead of stepping as the vertices are
	// rebuilt.
	vec2 cuv = clamp((wpos.xz + vec2(world_half)) / (world_half * 2.0),
		vec2(0.0), vec2(1.0));
	vec3 base = pow(biome_at(wpos.xz, wpos.y, gn.y,
		texture(climate, cuv).rg), vec3(2.2));
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
	float slope = 1.0 - clamp(gn.y, 0.0, 1.0);
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
	m.set_shader_parameter("climate", _bake_climate())
	m.set_shader_parameter("world_half", Sim.WORLD_HALF)
	m.set_shader_parameter("water_level", Sim.WATER_LEVEL)
	# Who bends the ground onto the planet.
	#
	# On the flat world the field is a plane and the shader curves it. On the
	# planet the field is already a function of a direction, so the heights come
	# back curved and the shader must leave them alone -- bending them a second
	# time drops the horizon twice as fast as it should and the ground closes
	# over your head at a hundred kilometres.
	m.set_shader_parameter("curve_radius", 0.0 if Sim.globe else Sim.PLANET_R)
	_climate_frame(m)
	return m

## Tell the ground where it is on the planet, so its climate can be a fact about
## the place rather than about the chart. Called again whenever the chart moves.
func _climate_frame(m: ShaderMaterial) -> void:
	m.set_shader_parameter("round_world", 1.0 if Sim.globe else 0.0)
	m.set_shader_parameter("planet_r", Sim.PLANET_R)
	m.set_shader_parameter("climate_squeeze", Sim.CLIMATE_SQUEEZE)
	m.set_shader_parameter("season_amp", Sim.SEASON_AMP)
	m.set_shader_parameter("season", Sim.season)
	_ground_mats.append(m)
	m.set_shader_parameter("chart_origin", Sim.chart_origin)
	m.set_shader_parameter("chart_east", Sim.chart_east)
	m.set_shader_parameter("chart_south", Sim.chart_south)
	m.set_shader_parameter("planet_north", Sim.PLANET_NORTH)

## The chart has moved: the ground's idea of where it is has moved with it.
## Asked for and not yet arrived, and whether the chart moved again meanwhile.
var _clim_want := false
var _clim_again := false

func rechart() -> void:
	if _mat == null:
		return
	_climate_frame(_mat)
	# and the climate picture itself, which is drawn over the ground the chart
	# is on rather than over a fixed square of world
	#
	# Asked for, not waited on. A million texels of two noise fields is a
	# twentieth of a second on its own and half a second while the map sheet is
	# being drawn beside it, and both used to land on the frame the chart moved.
	# The ground keeps the climate it has until this arrives, which is a few
	# frames of colour drawn for the country next door.
	if Sim.globe and not _ask_climate():
		_clim_again = true

func _ask_climate() -> bool:
	if not Sim.native.climate_request(CLIMATE_N, Sim.WORLD_HALF):
		return false
	_clim_want = true
	_clim_again = false
	return true

## Take a finished climate picture, if there is one. Pumped every frame by the
## world.
func pump_climate() -> void:
	if _clim_want and Sim.native.climate_ready():
		var buf: PackedByteArray = Sim.native.climate_take()
		if buf.size() == CLIMATE_N * CLIMATE_N * 4 and _mat != null:
			var img := Image.create_from_data(CLIMATE_N, CLIMATE_N, false,
				Image.FORMAT_RGH, buf)
			if OS.has_feature("headless") or OS.is_debug_build():
				climate_img = img.duplicate()   # for the harness to sample
			_mat.set_shader_parameter("climate",
				ImageTexture.create_from_image(img))
		_clim_want = false
	if _clim_again and not _clim_want:
		_ask_climate()

## How much of the ground to draw, against the planet body fading in behind it.
## Both surfaces are told, or the sea stays behind after the land has gone.
func set_ground_fade(f: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("ground_fade", f)
	if _sea_mat != null:
		_sea_mat.set_shader_parameter("ground_fade", f)

const CLIMATE_N := 1024               # texels across the whole world

## Temperature and moisture, rasterised once over the world.
##
## Both are low-frequency climate fields -- the shortest wavelength in either is
## about thirty kilometres -- so at 1.2 km to a texel a linear fetch reproduces
## them to well under the width of the bands they draw. Sampling them per
## fragment is what lets the biome rule run where the ground is drawn instead of
## at the corners of a cell.
func _bake_climate() -> ImageTexture:
	var n := CLIMATE_N
	var t0 := Time.get_ticks_msec()
	var buf: PackedByteArray
	# On the planet this is a picture of the country under the chart, and the
	# chart moves -- so it is neither the same picture as last time nor worth
	# keeping on disk.
	if Sim.globe:
		buf = Sim.native.climate_map_globe(n, Sim.WORLD_HALF)
	else:
		var cached: Variant = WorldBake.get_baked("climate_%d" % n)
		if cached is PackedByteArray \
				and (cached as PackedByteArray).size() == n * n * 4:
			buf = cached
		else:
			buf = Sim.native.climate_map(n, Sim.WORLD_HALF)
			WorldBake.put("climate_%d" % n, buf)
	stats["climate_ms"] = Time.get_ticks_msec() - t0
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGH, buf)
	if OS.has_feature("headless") or OS.is_debug_build():
		climate_img = img.duplicate()   # for the harness to sample
	return ImageTexture.create_from_image(img)

## The climate texture as an image, kept only where something will measure it.
var climate_img: Image = null

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
	var key := "ground_mask_%d_%d" % [int(mask_centre.x), int(mask_centre.y)]
	var cached: Variant = WorldBake.get_baked(key)
	if cached is PackedByteArray and (cached as PackedByteArray).size() == n * n * 2:
		return _mask_texture(cached, n, t0)
	# The shapes, then one call. Sixteen million texels against nine thousand
	# capsules is the kind of arithmetic there is no point doing anywhere else:
	# the extension buckets the shapes by row and fills the rows across every
	# core, where this was a pair of nested loops per capsule in script.
	var discs := PackedFloat32Array()      # x, z, solid, fade, channel
	for pad in Sim._town_pads:
		var pc: Vector2 = pad["c"]
		var pr: float = pad["r"]
		if not _in_box(pc, pr * 1.4):
			continue
		discs.append_array(PackedFloat32Array([pc.x, pc.y, pr * 1.02, pr * 1.32, 1.0]))
	var caps := PackedFloat32Array()       # ax, az, bx, bz, solid, fade, channel
	# the network: trunk roads wide, streets narrow
	for src in [[Sim.ROADS, 9.0, 30.0, 40.0], [Sim._segments, 5.0, 13.0, 20.0]]:
		var solid: float = src[1]
		var fade: float = src[2]
		var reach: float = src[3]
		for r in (src[0] as Array):
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			if not _in_box(a, reach) and not _in_box(b, reach):
				continue
			caps.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y,
				solid, fade, 0.0]))
	var made: Array = Sim.native.ground_mask(discs, caps, n, MASK_HALF,
		mask_centre)
	var buf: PackedByteArray = made[0]
	var cover: Vector2 = made[1]
	stats["mask_road_px"] = int(cover.x)
	stats["mask_town_px"] = int(cover.y)
	stats["mask_m_per_texel"] = snappedf(MASK_HALF * 2.0 / float(n), 0.01)
	WorldBake.put(key, buf)
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
	# Timed for the same reason the chart move is: it happens while you are
	# flying, it is sixteen million texels, and nothing was watching it.
	var t0 := Time.get_ticks_msec()
	mask_centre = c
	_mat.set_shader_parameter("mask_centre", mask_centre)
	_mat.set_shader_parameter("ground_mask", _bake_ground_mask())
	print("[mask] the painted ground moved to %s: %d ms (%d of it rasterising)" % [
		str(c.round()), Time.get_ticks_msec() - t0,
		int(stats.get("mask_ms", 0))])

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

## Is any of this worth stamping, or is it in a different part of the world?
## Clamping put every distant town and road on the edge texels of the box, as a
## smear down one side of the map.
func _in_box(c: Vector2, r: float) -> bool:
	return absf(c.x - mask_centre.x) < MASK_HALF + r \
		and absf(c.y - mask_centre.y) < MASK_HALF + r

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
var debug_pop: Array = []
var debug_seen: Dictionary = {}
var debug_nb_bad := 0

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
## What the last look at the tree asked for, so a chunk that finishes building
## after the viewer has moved on is not hung in the tree anyway.
var _want_keys: Dictionary = {}
## Whether the world has been brought fully up to date at least once. Until it
## has, a chunk arriving is the world being built rather than a hand-over.
var _settled := false

func build() -> void:
	prepare()
	flush_pending()

## Everything that has to happen before a single chunk can be built, and the
## queue filled -- but nothing built. The loading screen pumps `flush_pending`
## from there so the window keeps painting; `build` is the same thing in one
## blocking go, for the harnesses.
func prepare() -> void:
	# What the tree has measured is a property of the height field and of
	# nothing else, so it survives between runs. It keeps growing as you fly
	# somewhere the tree has not had to think about before, and whatever it has
	# learned by the end of the session goes back to disk.
	#
	# Error and high point together, sixteen bytes a node. They used to be two
	# tables and only the errors were written: a run off a bake found the error
	# already known, never filled the high point in, and read every node's high
	# ground as zero. Nothing in the world is seabed on that reading, and the
	# eye's height above a mountain is measured from the sea -- so a warm start
	# and a cold one built the country at different levels of detail, which is
	# not a failure anything was looking for.
	var cached: Variant = WorldBake.get_baked("node_stats")
	if cached is PackedByteArray and not (cached as PackedByteArray).is_empty():
		Sim.native.terrain_stats_put(cached)
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
## Is this point covered by the tree at all? The root is one square and the
## outermost leaves have nothing on the far side of them.
static func in_root(x: float, z: float) -> bool:
	var h := ROOT_SPAN * 0.5
	return absf(x) < h and absf(z) < h

## What depth the tree draws a point at, by descent from the root. Zero when the
## point is outside the root entirely. The harness's second opinion about every
## neighbour lookup the walk makes.
func depth_at(x: float, z: float, eye: Vector3) -> int:
	return Sim.native.terrain_depth_at(x, z, eye)

## The leaves that should exist for this eye position.
##
## The descent, the error measure and the neighbour lookups are all in the
## extension. It walks about ninety thousand nodes and every leaf then probes
## its four neighbours, and in script that was 4.1 ms every time the eye moved
## 120 m -- a dropped frame twice a second at cruise, which is the kind of
## stutter no frame-rate average shows. Worse, a node the tree had not seen
## before paid 353 height samples for its error one node at a time, on the
## thread walking the tree, so flying into new country cost more than flying
## over old. Over there a whole level of new nodes is measured in one pass
## across every core.
##
## What comes back is twelve numbers a leaf: depth, the two grid indices, what
## each of the four edges meets, which edges face a finer neighbour, and the
## four unclamped lookups the harness checks. Turning them into keys is all
## that is left here, and there are only a few hundred.
func _wanted(eye: Vector3) -> Dictionary:
	var flat: PackedInt32Array = Sim.native.terrain_tree(eye)
	var out: Dictionary = {}
	var leaves: Dictionary = {}
	if debug_count:
		for i in range(0, flat.size(), 12):
			leaves[_node_key(flat[i], flat[i + 1], flat[i + 2])] = flat[i]
	for i in range(0, flat.size(), 12):
		var d2: int = flat[i]
		var ix2: int = flat[i + 1]
		var iz2: int = flat[i + 2]
		var nb: Array = [flat[i + 3], flat[i + 4], flat[i + 5], flat[i + 6]]
		var fine: int = flat[i + 7]
		if debug_count:
			_check_leaf(d2, ix2, iz2, flat, i, leaves, eye)
		out["%d:%d:%d:%d,%d,%d,%d:%d" % [d2, ix2, iz2, nb[0], nb[1], nb[2],
			nb[3], fine]] = [d2, ix2, iz2, nb, fine]
	return out

## Both halves of what `--lodtest` gates on, for one leaf.
##
## A leaf may not contain another leaf: if one does, the descent has both split
## a node and kept it, and everything downstream of that -- seams, conforming,
## the lot -- is measuring a shape that cannot exist. And every neighbour lookup
## has to agree with a full descent from the root, which is the slow answer to
## the same question.
func _check_leaf(cd: int, cx: int, cz: int, flat: PackedInt32Array, at: int,
		leaves: Dictionary, eye: Vector3) -> void:
	var ax := cx
	var az := cz
	for up in range(cd - 1, 0, -1):
		ax = ax >> 1 if ax >= 0 else -((-ax + 1) >> 1)
		az = az >> 1 if az >= 0 else -((-az + 1) >> 1)
		if leaves.has(_node_key(up, ax, az)):
			debug_nb_bad += 1
			if debug_nb_bad <= 3:
				print("[nb] leaf d%d %d,%d sits inside leaf d%d %d,%d" % [
					cd, cx, cz, up, ax, az])
			break
	var span := span_at(cd)
	var x0 := float(cx) * span
	var z0 := float(cz) * span
	var half := span * 0.5
	var step := span / float(CELLS) * 0.5
	var probes := [
		Vector2(x0 - step, z0 + half),
		Vector2(x0 + span + step, z0 + half),
		Vector2(x0 + half, z0 - step),
		Vector2(x0 + half, z0 + span + step),
	]
	for ci in 4:
		var pv: Vector2 = probes[ci]
		# A probe off the edge of the world has no neighbour to disagree about,
		# and both sides say so in their own way.
		if not in_root(pv.x, pv.y):
			continue
		var descent := depth_at(pv.x, pv.y, eye)
		if descent != flat[at + 8 + ci]:
			debug_nb_bad += 1
			if debug_nb_bad <= 4:
				print("[nb] leaf d%d at %d,%d side %d: lookup says %d, descent says %d" % [
					cd, cx, cz, ci, flat[at + 8 + ci], descent])

## Move the viewer. Cheap when nothing has changed: the wanted set is compared
## against what is live and only the difference is touched. Because the tree is
## anchored to the world and not to the eye, "nothing has changed" is the
## overwhelmingly common case -- flying a straight line across open sea rebuilds
## nothing at all.
func recentre(eye: Vector3, immediate := false) -> void:
	# Thirty metres, not three hundred.
	#
	# The blend a chunk arrives with is set by how far away it is when it is
	# built, and the finest level's whole blend runs from 480 m to 960 m. Only
	# reconsidering the tree every 300 m meant a hand-over could be spotted 300 m
	# late, and the chunk then appeared a third of the way through its blend
	# instead of at the start of it: measured over a 22 km run, the mean blend at
	# appearance was 0.73 and half of every chunk built arrived under 0.9. That
	# is the ground visibly changing shape in front of you, and it is the thing
	# no seam or churn test was looking at.
	# A hundred and twenty metres. Thirty was chosen to make hand-overs prompt,
	# and measurement said prompt hardly mattered -- the blend at appearance
	# barely moved between 300 m and 30 m. What thirty did cost was a full look
	# at the tree eight times a second, nine milliseconds each, which is a
	# stutter every eighth of a second while you fly. The lead the world adds
	# along the flight path is what actually gets chunks built early.
	if not immediate and _centre.distance_squared_to(eye) < 14400.0:
		return
	# A jump is not a hand-over. `immediate` is how the world is told the eye
	# has been put somewhere rather than flown there -- a teleport, a respawn, a
	# harness setting up -- and everything that arrives afterwards is the world
	# being built at the new place, from nothing, with nothing to pop from. Left
	# counted, a single teleport contributed 87 "pops" to a 22 km run that had
	# not started yet.
	if immediate:
		_settled = false
	var _pw := Sim.prof_at()
	var want := _wanted(eye)
	Sim.prof_end(&"terrain.tree", _pw)
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
	_want_keys = want
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
## The work of a chunk is 289 height samples and the vertex assembly -- the
## three thousand biome colours it used to bake per chunk went with the vertex
## colours, now that the ground shader works its colour out per fragment -- and
## none of it touches the scene tree -- so it goes to the worker
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
	var _pf := Sim.prof_at()
	var made := _flush_inner(budget)
	Sim.prof_end(&"terrain.build", _pf)
	return made

func _flush_inner(budget: int) -> int:
	var made := _collect()
	if budget < 0:
		# Everything, now, in one call -- see `build_queued`. Anything already
		# out with the pool is taken back first, or it would land on top of what
		# this builds.
		if _batch_id != -1:
			WorkerThreadPool.wait_for_group_task_completion(_batch_id)
			_batch_done = true
			made += _collect()
		made += build_queued(_pending.size())
		stats["chunks"] = _live.size()
		# The world is now standing: everything wanted is up. Anything that
		# arrives after this is replacing something, which is the only kind of
		# arrival that can be seen to happen.
		_settled = true
		return made
	if _batch_id == -1:
		_dispatch(budget)
	stats["chunks"] = _live.size()
	return made

## Build everything queued, here and now, in one call.
##
## The engine's worker pool gave nothing on this. Measured, three hundred and
## forty chunks cost 95 ms built one after another on a single thread and about
## 120 ms of wall clock spread over eight of the pool's -- no parallelism at all,
## plus a four frame round trip a batch to dispatch and collect. The work is
## pure arithmetic in the extension, where the cores are already used; what has
## to happen on this thread is turning the arrays into meshes, and that is the
## same however the arrays arrived.
##
## Used where blocking is the right answer: the loading screen, and a harness.
## In flight the queue is still metered a few chunks at a time.
func build_queued(n: int) -> int:
	if _pending.is_empty() or n <= 0:
		return 0
	Sim.push_decks()
	var take := mini(n, _pending.size())
	var jobs := PackedInt32Array()
	jobs.resize(take * 8)
	var batch: Array = []
	var w := 0
	for i in take:
		var job: Array = _pending.pop_front()
		batch.append(job)
		var a: Array = job[1]
		var nb: Array = a[3]
		jobs[w] = int(a[0])
		jobs[w + 1] = int(a[1])
		jobs[w + 2] = int(a[2])
		jobs[w + 3] = int(nb[0])
		jobs[w + 4] = int(nb[1])
		jobs[w + 5] = int(nb[2])
		jobs[w + 6] = int(nb[3])
		jobs[w + 7] = int(a[4])
		w += 8
	var out: Array = Sim.native.chunk_build_many(jobs)
	var made := 0
	for i in batch.size():
		var key: String = (batch[i] as Array)[0]
		made += 1
		if not _want_keys.has(key):
			continue
		var mi := _commit(batch[i], [out[i * 5], out[i * 5 + 1],
			out[i * 5 + 2], out[i * 5 + 3], out[i * 5 + 4]])
		if mi != null:
			_live[key] = mi
			var b := _base_key(key)
			if _retire.has(b):
				_stash(b)
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
	# The decks, as they are right now. A carrier under way carries her deck
	# with her, so this is the one part of the world the extension cannot hold
	# once and forget; it is handed over here, on the main thread, before the
	# batch that will read it goes out.
	Sim.push_decks()
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
	# Waited on exactly once.
	#
	# A group task may be waited on once and once only -- the wait is what frees
	# it -- and `_flush_inner` waits itself when it runs the queue to the end.
	# Waiting again here is the "Invalid Group ID" the console has printed on
	# every launch: harmless, and exactly the kind of noise that hides a real
	# error the next time one turns up.
	if not _batch_done:
		WorkerThreadPool.wait_for_group_task_completion(_batch_id)
	_batch_id = -1
	_batch_done = false
	var made := 0
	for i in _batch.size():
		var key: String = (_batch[i] as Array)[0]
		# Still wanted?
		#
		# `recentre` filters the queue, but a batch already out with the worker
		# pool cannot be recalled -- and its chunks were committed into the live
		# set regardless of whether the viewer had moved on. That put leaves
		# from an old viewpoint back on top of the current ones: measured, 24
		# pairs of overlapping leaves, a depth 12 chunk sitting inside a depth 7
		# one, both drawing the same ground at different detail. It is the
		# partition breaking, and every seam and blend number downstream of it
		# was measuring a shape that cannot exist.
		if not _want_keys.has(key):
			made += 1
			continue
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
	# Hidden before it is freed, always. `queue_free` does not take effect until
	# the end of the frame, so a chunk freed while its replacement was already
	# up drew the same ground twice for that frame -- one frame of two surfaces
	# fighting for the same pixels, every time a chunk went away.
	(n as MeshInstance3D).visible = false
	if k == "" or _cache.has(k):
		n.queue_free()
		return
	_cache[k] = n
	_cache_age.append(k)
	while _cache_age.size() > CACHE_MAX:
		var old_k: String = _cache_age.pop_front()
		var old_n: Node = _cache.get(old_k)
		_cache.erase(old_k)
		if is_instance_valid(old_n):
			(old_n as MeshInstance3D).visible = false
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
	arr[Mesh.ARRAY_TEX_UV2] = out[3]
	arr[Mesh.ARRAY_TANGENT] = out[4]
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
		var times: int = int(debug_builds.get(bk, 0)) + 1
		debug_builds[bk] = times
		# Ever, not since the counter was last reset. `debug_builds` gets
		# cleared between phases of a test, and clearing it made every chunk
		# built before look brand new the next time a neighbour changed level --
		# so ordinary variant rebuilds, at whatever distance they happened, were
		# counted as hand-overs.
		var first_ever: bool = not debug_seen.has(bk)
		debug_seen[bk] = true
		# And how far through its blend this chunk is at the instant it appears.
		# One means it arrives shaped exactly like the level above and the
		# hand-over cannot be seen; anything less is a step, and it is measured
		# at the corner nearest the eye because that is where it shows.
		var sp := span_at(depth)
		var bx := float(int(a[1])) * sp
		var bz := float(int(a[2])) * sp
		var ddx: float = maxf(maxf(bx - _centre.x, _centre.x - (bx + sp)), 0.0)
		var ddz: float = maxf(maxf(bz - _centre.z, _centre.z - (bz + sp)), 0.0)
		var lo := SPLIT_K * sp
		# Only the first time this piece of ground appears at this detail. A
		# chunk is also rebuilt when a neighbour changes level, and that comes
		# back as the same surface with a differently conformed edge -- nothing
		# moves, nothing pops, and counting those as appearances buried the real
		# number under twice as many non-events.
		# ...and only once the world is standing.
		#
		# A pop is a *visible change*, and that needs a before as well as an
		# after. At load the whole world is built at once from nothing with the
		# eye standing still: hundreds of chunks arrive at whatever blend their
		# distance happens to imply, about a half on average, and not one of
		# them pops, because there was nothing there to pop from. Counted as
		# appearances they were most of the failure and they hid whatever the
		# real number was.
		if first_ever and _settled:
			var ddy: float = maxf(_centre.y - node_top(depth, int(a[1]),
				int(a[2])), 0.0)
			var dd := sqrt(ddx * ddx + ddz * ddz + ddy * ddy)
			debug_pop.append([clampf((dd - lo) / maxf(lo, 1.0), 0.0, 1.0),
				depth, dd, lo, bx, bz])
	# Only the two finest levels -- a 960 m leaf and smaller. A shadow map
	# spends its resolution on whatever is in it, and a node the size of a
	# county in there costs every close shadow its definition.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if depth >= MAX_DEPTH - 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	stats["seam"] = maxf(float(stats.get("seam", 0.0)), float(out[2]))
	stats["tris"] += CELLS * CELLS * 2
	return mi

func pending_count() -> int:
	return _pending.size() + _batch.size()

## Everything a chunk is, as plain arrays: vertices, normals, the seam the
## stitching left, the morph and the coarse normal.
##
## The whole of it is in the extension. It was four hundred lines here -- the
## grid, the conformed edges, the parent surface, two sets of vertex normals,
## the faces and the skirt -- walking packed arrays a Vector3 at a time on a
## worker thread, and it was the largest single item in world generation. What
## is left on this side is turning the arrays into a mesh, which is the part
## that has to happen on the main thread anyway.
##
## Called on a worker, so it may read the height field and nothing else.
func _chunk_arrays(depth: int, ix: int, iz: int, nb: Array, fine: int) -> Array:
	return Sim.native.chunk_build(depth, ix, iz,
		PackedInt32Array([int(nb[0]), int(nb[1]), int(nb[2]), int(nb[3])]), fine)

## A leaf's identity without its neighbour state, so a rebuild triggered only by
## a change next door can be matched to the chunk it supersedes.
func _base_key(k: String) -> String:
	var bits := k.split(":")
	return "%s:%s:%s" % [bits[0], bits[1], bits[2]] if bits.size() >= 4 else k

## Where a conformed edge vertex sits, and which of the chunk's grid points it
## is. Written once and read by the probe, the stitching and the residual, so
## the three cannot walk the border in different orders.
## The sea. Curvature is already in the mesh; this puts the swell on top of it
## and gives the surface some life.
const SEA_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform float swell_a = 1.25;
uniform float swell_b = 0.75;
uniform float swell_c = 0.42;
uniform vec2 ka = vec2(0.0121, 0.0067);
uniform vec2 kb = vec2(-0.0074, 0.0138);
uniform vec2 kc = vec2(0.062, 0.065);
uniform float wa = 0.368;
uniform float wb = 0.392;
uniform float wc = 0.939;
// Handed in rather than taken from TIME: the hulls advance their own clock and
// the two must not drift.
uniform float sea_time = 0.0;
// Fades with the ground it belongs to; already transparent, so no dither.
uniform float ground_fade = 1.0;
// Whether the sea is a sphere about `up_axis` or a flat shell about the origin.
uniform float round_world = 0.0;
uniform vec3 up_axis = vec3(0.0);

varying vec3 wpos;

// The identical expression Sim.wave_at uses. If these two ever disagree, ships
// float above or sink into a sea that looks nothing like what they are on.
float swell(vec2 p) {
	return swell_a * sin(ka.x * p.x + ka.y * p.y + sea_time * wa)
		+ swell_b * sin(kb.x * p.x + kb.y * p.y + sea_time * wb)
		+ swell_c * sin(kc.x * p.x + kc.y * p.y + sea_time * wc);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Up is not `y` on a sphere. On the flat shell the two are the same and
	// lifting the vertex along `y` is right; on the planet it has to be lifted
	// along its own radius, or the swell shears the sea sideways and on the far
	// side of the world lifts it *into* the planet. `round_world` is what tells
	// the two apart, and `up_axis` is the centre it is round about.
	vec3 up = round_world > 0.5 ? normalize(w - up_axis) : vec3(0.0, 1.0, 0.0);
	float lift = swell(w.xz);
	VERTEX += up * lift;
	wpos = w + up * lift;
	// the surface normal follows the swell, which is what makes the light run
	// along the crests
	float e = 6.0;
	float hx = swell(w.xz + vec2(e, 0.0)) - swell(w.xz - vec2(e, 0.0));
	float hz = swell(w.xz + vec2(0.0, e)) - swell(w.xz - vec2(0.0, e));
	vec3 flat_n = normalize(vec3(-hx, 2.0 * e, -hz));
	// The ripple is worked out about a flat up; on the planet it is carried
	// onto the surface's own up so the highlight still runs along the crests.
	NORMAL = round_world > 0.5
		? normalize(up * flat_n.y + vec3(flat_n.x, 0.0, flat_n.z))
		: flat_n;
}

void fragment() {
	// small chop on top of the swell, in the normal only
	vec2 q = wpos.xz;
	vec3 ripple = vec3(
		sin(q.x * 0.42 + sea_time * 1.9) + sin(q.y * 0.61 + sea_time * 1.1),
		0.0,
		sin(q.y * 0.37 + sea_time * 2.1) + sin(q.x * 0.55 + sea_time * 0.9));
	NORMAL = normalize(NORMAL + ripple * 0.05);
	ALBEDO = vec3(0.07, 0.19, 0.28);
	ROUGHNESS = 0.06;
	METALLIC = 0.45;
	RIM = 0.7;
	ALPHA = 0.86 * ground_fade;
}
"""

var _sea_mat: ShaderMaterial = null

## The sea has its own clock, advanced by Sim, and the shader is handed it every
## frame so the drawn swell and the swell the hulls ride stay in step.
func _process(_dt: float) -> void:
	if _sea_mat != null:
		_sea_mat.set_shader_parameter("sea_time", Sim.sea_time)


func _water() -> void:
	# The sea is a shell, not a plate. A flat plane against curved ground floods
	# the far half of the world: sixty kilometres out the land has dropped 283 m
	# and a level sea is 283 m over the top of it. Built as a grid that follows
	# the same d^2/2R the ground does, so the coastline stays where it is drawn.
	# On the planet it is a sphere, because the sea is. A shell over the near
	# 1400 km ends in a rim you can fly to and look over the edge of, and with
	# the world square gone there is no reason for the water to be square
	# either. Same shader, same swell, same clock -- only the surface it is
	# painted on is closed.
	var pm := _sea_sphere(120, 60) if Sim.globe \
		else _sea_shell(Sim.WORLD_HALF * 1.2, 96)
	# A shader, because the swell has to be drawn where a hull actually rides
	# it. The constants and the clock come from Sim, which is the same pair the
	# ships read — a sea drawn by one formula and floated on by another is worse
	# than a flat one.
	var sh := Shader.new()
	sh.code = SEA_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	_sea_mat = m
	# The sea sorts before every other transparent thing. It is a single mesh
	# the width of the world, so its sort origin is nowhere near the piece of
	# water you are actually looking at, and without this it happily draws over
	# splashes, explosions and anything else at the surface.
	m.render_priority = -8
	m.set_shader_parameter("swell_a", Sim.SWELL_A)
	m.set_shader_parameter("swell_b", Sim.SWELL_B)
	m.set_shader_parameter("ka", Sim.SWELL_KA)
	m.set_shader_parameter("kb", Sim.SWELL_KB)
	m.set_shader_parameter("wa", Sim.SWELL_WA)
	m.set_shader_parameter("wb", Sim.SWELL_WB)
	m.set_shader_parameter("swell_c", Sim.SWELL_C)
	m.set_shader_parameter("round_world", 1.0 if Sim.globe else 0.0)
	m.set_shader_parameter("up_axis", Sim.planet_centre)
	m.set_shader_parameter("kc", Sim.SWELL_KC)
	m.set_shader_parameter("wc", Sim.SWELL_WC)
	var mi := MeshKit.mi(pm, "Water")
	mi.material_override = m
	# The sphere is built about the planet's centre and already carries sea
	# level in its radius; the flat shell is built about the origin and is set
	# down at it.
	mi.position = Sim.planet_centre if Sim.globe \
		else Vector3(0, Sim.WATER_LEVEL, 0)
	# It is 12742 km across and wraps the camera, so no culling volume the
	# engine works out for it can be right in a useful direction.
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## A curved sheet for the sea: a grid over the world, each vertex dropped by the
## sagitta at its own distance from the origin, exactly as the ground and the
## terrain shader are.
## The sea as the planet's own surface: a sphere at sea level.
##
## Vertices are placed on the sphere and the shader lifts them by the same swell
## a hull rides, so the two agree everywhere rather than only near the middle of
## a patch. The normal is the outward radius, which is what makes the specular
## roll off toward the horizon on a round world instead of staying flat.
func _sea_sphere(segs: int, rings: int) -> ArrayMesh:
	var r: float = Sim.PLANET_R + Sim.WATER_LEVEL
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in rings + 1:
		var th: float = PI * float(j) / float(rings)
		for i in segs + 1:
			var ph: float = TAU * float(i) / float(segs)
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			verts.append(u * r)
			norms.append(u)
			uvs.append(Vector2(float(i) / float(segs), float(j) / float(rings)))
	for j2 in rings:
		for i2 in segs:
			var a: int = j2 * (segs + 1) + i2
			var b: int = a + 1
			var c: int = a + segs + 1
			var d: int = c + 1
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func _sea_shell(half: float, n: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var step: float = half * 2.0 / float(n)
	for j in n + 1:
		for i in n + 1:
			var x: float = -half + float(i) * step
			var z: float = -half + float(j) * step
			verts.append(Vector3(x, -Sim.planet_drop(x, z), z))
			# The shell's own normal leans with it, which is what makes the
			# specular roll off toward the horizon instead of staying flat.
			norms.append(Vector3(x, Sim.PLANET_R, z).normalized())
			uvs.append(Vector2(float(i) / float(n), float(j) / float(n)))
	for j in n:
		for i in n:
			var a: int = j * (n + 1) + i
			var b: int = a + 1
			var c: int = a + n + 1
			var d: int = c + 1
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

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


## The year has turned: the snow line and the treeline move with it.
func set_season(s: float) -> void:
	for m in _ground_mats:
		if is_instance_valid(m):
			(m as ShaderMaterial).set_shader_parameter("season", s)
