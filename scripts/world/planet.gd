class_name Planet
extends Node3D
## The planet as a body, for when the eye is too high for the ground to be worth
## building.
##
## The detailed world is a quadtree of chunks over a cap 983 km across, and it
## is the right thing to draw from a cockpit. From eighty kilometres up it is
## the wrong thing twice over: the horizon is 1000 km away so the whole cap is
## in view at once, and none of the detail it is spending triangles on subtends
## a pixel. This is the same ground as one low sphere with the relief painted on
## it -- the map's own baked image, which already covers exactly the same
## +-600 km -- and the two are crossfaded so there is no moment where the world
## changes.
##
## The sphere is drawn at its real radius and its real place, not in a scaled
## space near the camera. Scaled space is the usual trick and it is cheaper, but
## it puts the body a few kilometres from the eye where the depth buffer is
## concerned, so anything genuinely between you and the planet -- a satellite at
## seventy kilometres, a round on the way up to one -- comes out behind it. At
## real scale the depth is simply true, and the cost is a far plane that has to
## move, which is wanted anyway.

## Segments around the axis. This is what the limb is made of, so it is what
## faceting shows up in: 192 is 1.9 degrees, which at the distance the limb is
## ever seen from reads as a curve.
const SEGS := 192
## How far out from the theatre the fine rings run. Beyond this there is nothing
## but ocean and nothing to line up against, so the rings coarsen.
##
## Far enough to reach the *corners* of the mapped square, not its edges: at
## 0.12 the rings coarsened at 764 km and the +-600 km box reaches 848 km
## diagonally, so the four corners of the theatre were drawn with the ocean's
## triangles and stood 769 m off sea level.
const CAP_ANG := 0.145                # radians, about 924 km of surface
## Ring spacing inside the cap, in metres of surface. The sphere has to agree
## with the terrain it is fading into, and a ring every 15 km stands off the
## true surface by 4 m -- against the 850 m a uniform sphere of the same
## triangle count would manage over the same ground.
const CAP_STEP := 15_000.0
## Ring spacing outside it, in radians.
const BODY_STEP := 0.0327             # 1.9 degrees

## Altitude at which the ground starts giving way, and the one by which the
## sphere has it entirely. The lower figure is about where the horizon reaches
## as far as the cap does -- above it there is no more world to show, only more
## of the same world drawn smaller.
const FADE_LO := 38_000.0
const FADE_HI := 90_000.0
## What the eye can see, at each end of that. Forty-five kilometres is the
## cockpit far plane and everything is built around it.
##
## The planet does not need two diameters: from outside a sphere you can only
## ever see as far as the tangent, which from ninety kilometres up is 1071 km
## and from two hundred is 1600. Past that there is no planet to draw, so this
## is as far as the eye ever usefully reaches.
const FAR_LO := 45_000.0
const FAR_HI := 1_600_000.0
## How far out the ground is built, from anywhere on it: the terrain's root
## square is +-983 km.
const ROOT_REACH := 980_000.0
## The near plane has to come out with it. Godot's directional shadow culler
## builds its frustum points in single precision, and past a near-to-far ratio
## of a few million it cannot: at 0.25 m against 1200 km it fails every frame,
## on every light, and the shadows go with it. A metre of near plane buys the
## whole planet and clips nothing that is not already inside the cockpit.
const NEAR_LO := 0.25
const NEAR_RATIO := 1_400_000.0
const NEAR_MAX := 1.2

const SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// The relief the tactical map is drawn from -- the same bake, so the ground you
// fly over and the ground you see from orbit cannot disagree.
//
// Mipmapped and anisotropic: the body is seen from straight down to edge on at
// the limb, and without either the far half of the view sparkles.
uniform sampler2D relief : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// The same rule baked finer over the cap under the eye, with the ground's
// height in alpha: see `Planet._patch_window`. `patch_win` is the part of the
// sheet it covers -- u0, u1, v0, v1 -- and `patch_on` is whether there is one.
uniform sampler2D patch_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 patch_win = vec4(0.0, 1.0, 0.0, 1.0);
uniform float patch_on = 0.0;
// What a full alpha is worth in metres, and how much the slopes are steepened
// for being seen from hundreds of kilometres off. Real slopes averaged over a
// texel of a few kilometres are a degree or two, which the sun cannot pick out;
// eight brings the ranges and the river valleys up without turning every
// valley into a trench.
uniform float relief_top = 8000.0;
uniform float relief_gain = 8.0;
uniform float map_half = 600000.0;
// 0 hides the body, 1 draws it. The ground is dithering out over the same band.
uniform float fade = 0.0;
// The planet's frame: where its centre is, which way its north lies, and which
// way the middle of the theatre lies. Longitude is measured from the theatre,
// so the world lands on the planet where the world actually is.
uniform vec3 centre = vec3(0.0);
// The world's frame into the planet's: see the cloud shell, which had the same
// fault. `north` and `home` are the planet's own axes, the ones the sheet was
// baked about; a direction in the world has to be turned into that frame
// before it is looked up, or the picture is of whatever is under the chart's
// middle as if that were always the same place.
uniform mat3 to_planet = mat3(1.0);
uniform vec3 north = vec3(0.0, 0.0, -1.0);
uniform vec3 home = vec3(0.0, 1.0, 0.0);
uniform float radius = 6371000.0;
const float PI_ = 3.14159265359;
const float TAU_ = 6.28318530718;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Where this point is on the planet, as surface distances from the middle
	// of the theatre: longitude east of it and latitude north of it, both
	// turned back into metres so the world lands at its true size. Directly
	// over the theatre this comes out as the point's own x and z, which is what
	// makes the body agree with the terrain it is fading into.
	vec3 u = to_planet * normalize(wpos - centre);
	float lat = asin(clamp(dot(u, north), -1.0, 1.0));
	// East and the theatre's own meridian, which together fix where longitude
	// is measured from.
	vec3 east = normalize(cross(north, home));
	float lon = atan(dot(u, east), dot(u, home));
	// Straight onto the sheet, which is the generated planet: longitude across,
	// latitude down. The sheet already carries the ice caps and the theatre --
	// it was baked from the same generator, so there is nothing to paint over
	// the top of it here.
	vec2 uv = vec2(lon / TAU_ + 0.5, 0.5 - lat / PI_);
	// The footprint of the pixel on the sheet, taken across the seam where
	// longitude wraps. Left to the hardware, the jump from one edge of the
	// sheet to the other reads as a pixel the size of the planet and draws
	// the smallest mip down the far meridian: a dark line pole to pole.
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	gx.x -= round(gx.x);
	gy.x -= round(gy.x);
	vec3 col = textureGrad(relief, uv, gx, gy).rgb;
	vec3 n_p = u;
	if (patch_on > 0.5) {
		float us = patch_win.y - patch_win.x;
		float vs = max(patch_win.w - patch_win.z, 1e-6);
		float uc = (patch_win.x + patch_win.y) * 0.5;
		// Measured from the window's middle, the short way round, so a
		// window across the seam is one window and not two halves.
		vec2 pu = vec2((fract(uv.x - uc + 0.5) - 0.5) / us + 0.5,
			(uv.y - patch_win.z) / vs);
		vec2 px = vec2(gx.x / us, gx.y / vs);
		vec2 py = vec2(gy.x / us, gy.y / vs);
		vec2 edge = min(pu, 1.0 - pu);
		// A window that takes in every meridian has no east and west edge.
		if (us > 0.999) {
			edge.x = 1.0;
		}
		// Faded in from its own edge, so where the fine picture stops and
		// the whole-planet one carries on is not a line.
		float wgt = smoothstep(0.0, 0.08, min(edge.x, edge.y));
		if (wgt > 0.0) {
			vec4 p = textureGrad(patch_tex, pu, px, py);
			col = mix(col, p.rgb, wgt);
			// The slopes, from the height either side. Stepped by whatever
			// the pixel covers, never less than a texel, so a distant
			// mountain range is lit as a range and not as noise.
			float nt = float(textureSize(patch_tex, 0).x);
			float st = max(max(length(px), length(py)) * nt, 1.0) / nt;
			float a_e = textureGrad(patch_tex, pu + vec2(st, 0.0), px, py).a;
			float a_w = textureGrad(patch_tex, pu - vec2(st, 0.0), px, py).a;
			float a_n = textureGrad(patch_tex, pu - vec2(0.0, st), px, py).a;
			float a_s = textureGrad(patch_tex, pu + vec2(0.0, st), px, py).a;
			float h_e = a_e * a_e * relief_top;
			float h_w = a_w * a_w * relief_top;
			float h_n = a_n * a_n * relief_top;
			float h_s = a_s * a_s * relief_top;
			// Metres of ground across those two steps, east and north.
			float run_e = 2.0 * st * us * TAU_ * radius * max(cos(lat), 0.02);
			float run_n = 2.0 * st * vs * PI_ * radius;
			vec3 east_p = normalize(cross(north, u));
			vec3 north_p = cross(u, east_p);
			vec3 tilt = east_p * ((h_e - h_w) / run_e)
				+ north_p * ((h_n - h_s) / run_n);
			n_p = normalize(u - tilt * relief_gain * wgt);
		}
	}
	ALBEDO = col;
	// Back out of the planet's frame into the world's, and into the view.
	NORMAL = normalize((VIEW_MATRIX * vec4(n_p * to_planet, 0.0)).xyz);
	ROUGHNESS = 0.94;
	METALLIC = 0.0;
	// Opaque. It was drawn at an opacity of `fade` while the ground dithered
	// out over the same band, so through the whole of the hand-over, from
	// thirty-eight kilometres to ninety, the two together covered at most
	// three quarters of the picture -- and wherever the ground had not been
	// built yet, which is everywhere a rocket has just got to, the body alone
	// covered a third. The sky showed through the planet: patches with
	// straight edges where tiles were missing, and a ring where the built
	// ground ran out. The ground dithers away over a body that is always all
	// there, so between the two every pixel is one or the other.
}
"""

## The generated planet, and the sheet baked from it.
##
## Equirectangular, and read by both the body and the tactical globe, so the
## planet you see from orbit and the planet you see on the map are the same
## planet. One texel is 20 km. It was 39, which was only ever right for the
## planet seen whole: from a thousand kilometres up the country under you was
## a few dozen blocks. What is under the eye now comes from `_patch_window`;
## this is the rest of the ball, the limb and the far side.
const SHEET_W := 2048
const SHEET_H := 1024

## The finer picture of the cap the eye can see, baked in the background and
## laid over the sheet. Texels square; 2048 over the cap seen from a thousand
## kilometres is three and a half kilometres a texel, and under one at ninety.
const PATCH_RES := 2048
## How far round the planet it reaches from the point under the eye, in
## radians. At least far enough to cover the hand-over from the ground, and no
## further than the eye gains from. Past half a radian the ground is seen so
## edge on that the sheet does as well -- and a window that big reaches a pole
## from anywhere past sixty degrees, where it then has to take in every
## meridian and the 2048 texels across it are spread round the whole planet:
## at three quarters of a radian the country under a warhead coasting at
## 1200 km came out ten kilometres a texel east to west and smeared.
const PATCH_MIN := 0.06
const PATCH_MAX := 0.5
## How far the eye may move, or the cap grow or shrink, before the window is
## baked again, as a fraction of its own span.
const PATCH_SLACK := 0.2
## The window baked round a satellite view's focus: about 570 km either side.
const FOCUS_PATCH_ANG := 0.09
## The step between the sizes a window may be: see `_window_at`.
const PATCH_LADDER := 1.5
## Mirrors `sphere::BODY_RELIEF_TOP`: the height a full alpha stands for.
const RELIEF_TOP := 8000.0

var terrain_gen: PlanetTerrain
var sheet: ImageTexture
var _mi: MeshInstance3D
var _mat: ShaderMaterial
## The cap under the eye: the picture, the window of the sheet it is a picture
## of, the window a bake is in flight for, and the newest one wanted since.
## Kept apart for the reason the map's globe keeps its own apart -- a picture
## hung on the window asked for after it is a picture in the wrong place.
var _patch_tex: ImageTexture = null
var _patch_win := PackedFloat32Array()
var _patch_asked := PackedFloat32Array()
var _patch_next := PackedFloat32Array()
var _patch_next_cache := false
## The fine picture of a place the satellite view holds on is the same every
## time it is asked for (in the same season, by the same code), so it is kept
## on disk: read back on a worker the next time instead of baked again.
const PATCH_CACHE := "user://patch_cache"
## How much disk the kept pictures may take; the oldest go first past it.
const PATCH_CACHE_BYTES := 10_000_000_000
## Where the bake in flight is to be saved, if it is one worth keeping.
var _patch_save := ""
## A cached picture being read back.
var _disk_task := -1
var _disk_buf := PackedByteArray()
var _disk_path := ""
static var _code_sig := ""
## A picture being baked for the disk and not for the screen: see `warm`.
var _patch_warm := false
## How much of the body is being drawn, and so how much of the ground is not.
var fade := 0.0
## True once the ground is completely hidden and there is no reason to keep
## building it.
var dormant := false

## The direction from the planet's centre for a texel of the sheet. Longitude
## runs east from the theatre so the world lands where the world is.
func sheet_dir(u: float, v: float) -> Vector3:
	var lat: float = (0.5 - v) * PI
	var lon: float = (u - 0.5) * TAU
	var north: Vector3 = Sim.PLANET_NORTH
	var home := Vector3.UP
	var east: Vector3 = north.cross(home).normalized()
	return (north * sin(lat)
		+ (home * cos(lon) + east * sin(lon)) * cos(lat)).normalized()

## Colour the whole planet once, and keep it.
##
## Built in the extension, not here. Half a million texels evaluated one at a
## time in GDScript was 922 ms of a 4.4 s cold boot, and it also meant the rule
## that decides what the ground looks like existed twice -- which is exactly how
## a map stops matching the country it is a map of.
func bake_sheet() -> ImageTexture:
	var cached: Variant = WorldBake.get_baked("planet_sheet")
	var buf: PackedByteArray
	if cached is PackedByteArray \
			and (cached as PackedByteArray).size() == SHEET_W * SHEET_H * 3:
		buf = cached
	else:
		var t0 := Time.get_ticks_msec()
		buf = Sim.native.planet_sheet(SHEET_W, SHEET_H, Sim.PLANET_NORTH)
		if OS.is_debug_build():
			print("[planet] sheet baked: %d x %d in %d ms" % [
				SHEET_W, SHEET_H, Time.get_ticks_msec() - t0])
		WorldBake.put("planet_sheet", buf)
	var img := Image.create_from_data(SHEET_W, SHEET_H, false, Image.FORMAT_RGB8, buf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func build(_relief: Texture2D) -> void:
	position = Sim.planet_centre
	terrain_gen = PlanetTerrain.new(20260903, Sim.PLANET_R)
	sheet = bake_sheet()
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("relief", sheet)
	_mat.set_shader_parameter("map_half", Sim.WORLD_HALF)
	_mat.set_shader_parameter("fade", 0.0)
	_mat.set_shader_parameter("centre", Sim.planet_centre)
	_mat.set_shader_parameter("north", Sim.PLANET_NORTH)
	_mat.set_shader_parameter("home", Vector3.UP)
	_mat.set_shader_parameter("radius", Sim.PLANET_R)
	_mat.set_shader_parameter("relief_top", RELIEF_TOP)
	_mat.set_shader_parameter("patch_on", 0.0)
	_mi = MeshInstance3D.new()
	_mi.name = "PlanetBody"
	_mi.mesh = _sphere()
	_mi.material_override = _mat
	# Before the sea, which is -8. Both are transparent and the sea writes
	# depth, so drawn after it the body failed the depth test everywhere the
	# sea disc reaches -- fifteen hundred kilometres round the eye -- and from
	# altitude there was no ground under the haze at all, only the air and the
	# cloud deck over empty space. Drawn first, the sea composites over it as
	# it fades out, which is what the fade was for.
	_mat.render_priority = -9
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It is 12742 km across and centred on the camera's own planet, so no
	# culling volume Godot works out for it is ever going to be wrong in a
	# useful direction -- and getting it wrong once means the world vanishes.
	_mi.extra_cull_margin = 16384.0
	_mi.visible = false
	add_child(_mi)

## Ring angles from the pole to the far side: close together over the theatre,
## where the sphere has to agree with the ground, and coarse everywhere else,
## where all it has to do is look round.
func _ring_angles() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var th := 0.0
	var step: float = CAP_STEP / Sim.PLANET_R
	while th < CAP_ANG:
		out.append(th)
		th += step
	while th < PI:
		out.append(th)
		th += BODY_STEP
	out.append(PI)
	return out

## Clockwise seen from outside, which is Godot's front face -- the moon's
## winding, not the air's. This was wound the other way, so `cull_back` threw
## away the whole near side of the planet and what was drawn was the INSIDE of
## the far side: the picture of the wrong hemisphere, lit from behind, and only
## as far as the far plane reaches. Looking down from a few hundred kilometres
## the far wall under you is past the far plane, so there was a hole round the
## point below the eye with the sky showing through it and the cloud and air --
## which find the planet by arithmetic -- still painted over the gap. It went
## wherever the camera went. The air and cloud shells draw `cull_disabled`, so
## their winding never mattered and they are left alone.
##
## No tangents: there are no UVs to make them from and nothing sampling a
## normal map. Asking for them is an error, not a no-op.
func _sphere() -> ArrayMesh:
	var rings := PackedFloat64Array()
	for th in _ring_angles():
		rings.append(th)
	return MeshKit.globe(rings, SEGS, Sim.PLANET_R, true).commit()

## Called every frame with the eye. Works out how much planet and how much
## ground there should be, tells the ground, and moves the far plane out far
## enough to see a body two diameters deep.
func follow(cam: Camera3D, terrain: Node, scenery: Node) -> void:
	if _mi == null or cam == null:
		return
	var alt: float = Sim.altitude(cam.global_position)
	var f: float = clampf((alt - FADE_LO) / maxf(FADE_HI - FADE_LO, 1.0), 0.0, 1.0)
	fade = f * f * (3.0 - 2.0 * f)
	dormant = fade >= 0.999
	_mi.visible = fade > 0.001
	_mat.set_shader_parameter("fade", fade)
	# Drawn smaller for a spacecraft a long way out: see `LaunchVehicle._place`.
	_mi.scale = Vector3.ONE * Sim.view_scale
	_mat.set_shader_parameter("to_planet",
		Basis(Sim.chart_east, Sim.chart_origin, Sim.chart_south))
	# The fine cap under the eye. Asked for a little before the body starts
	# to show, so the hand-over from the ground is onto the fine picture and
	# not onto the whole-planet one with the fine one arriving half way.
	_collect_patch()
	if alt > FADE_LO - 10000.0 and not (cam is SatView and not (cam as SatView).settled()):
		_want_patch(_patch_window(cam), true)
	elif cam is SatView and (cam as SatView).focus_dir != Vector3.ZERO:
		# Coming down onto somewhere, or the menu holding over it: the moving
		# view never settles, so the ground there is baked ahead of it --
		# once, for the span the way down passes through -- and the descent
		# lands on the fine picture rather than on twenty-kilometre texels.
		_want_patch(_window_at((cam as SatView).focus_dir, FOCUS_PATCH_ANG), true)
	# Only once there is something out there to see. Left at 2600 km from the
	# ground the far plane would be paying for the whole cap on every frame of
	# a landing circuit.
	#
	# And far enough to reach the horizon, wherever the eye is. A fixed
	# sixteen hundred kilometres is past the horizon up to about two hundred
	# kilometres; a round on its arc or an ASAT climbing to a satellite goes
	# well above that, and from six hundred the edge of the planet is 2800 km
	# away. Everything past the far plane went -- the planet body, the cloud
	# deck -- while the air, which finds the planet by arithmetic rather than
	# by depth, went on painting its haze over the empty space where it had
	# been: a grey band standing where the limb should be, and the planet
	# looking as though it stopped short of its own horizon. The distance to
	# the horizon plus the air beyond it, which is visible past the edge.
	#
	# The same below the air, where the far plane was forty-five kilometres
	# whatever the height. The ground is built out to nearly a thousand: the
	# far plane cut it off at forty-five, and the air -- which hazes the
	# distance by integrating up to whatever depth it finds -- painted its blue
	# over the empty space past the cut. From ten kilometres the horizon is 357
	# km away and you saw a flat band from 45 onwards. The depth fog never hid
	# this: it runs in depth mode at zero density, which in Godot is no fog.
	# So: out to the horizon, and two hundred kilometres beyond it for the
	# mountains that stand up over it.
	var r: float = Sim.PLANET_R
	var to_limb: float = sqrt(maxf((r + alt) * (r + alt) - r * r, 0.0))
	var beyond: float = sqrt(maxf((r + 100000.0) * (r + 100000.0) - r * r, 0.0))
	var ground_reach: float = minf(to_limb + 200000.0, ROOT_REACH)
	cam.far = maxf(FAR_LO, ground_reach)
	if fade > 0.0:
		cam.far = maxf(cam.far, maxf(lerpf(FAR_LO, FAR_HI, fade), (to_limb + beyond) * 1.05))
	if Sim.view_scale < 0.999:
		# the whole shrunken body, and the moon beyond it if it is that close
		cam.far = maxf(cam.far, (r + alt) * 1.3)
	cam.near = clampf(cam.far / NEAR_RATIO, NEAR_LO, NEAR_MAX)
	# The satellite view has nothing under its lens, and from far out the 1.2 m
	# cap put far over near past what the shadow culler can take (above): from
	# about 9800 km up the sun went, and the planet and its cloud went black.
	# Its near plane goes out with the far one.
	if cam is SatView:
		cam.near = clampf(cam.far / NEAR_RATIO, NEAR_LO, maxf(alt * 0.05, NEAR_LO))
	# A camera that carries something right under the lens -- the rifle on a
	# man's cheek -- says how close it needs to see. Left at a quarter metre
	# the plane sliced the stock and receiver open in first person, and worse
	# looking up, where the butt comes up nearer the eye. The depth buffer is
	# reversed, so the far ground does not pay for it.
	if cam.has_meta(&"near_need"):
		cam.near = minf(cam.near, float(cam.get_meta(&"near_need")))
	# riding a bullet: the chase camera's own planes (see `ChaseCamera`)
	if cam.has_meta(&"ride_planes"):
		var rp: Vector2 = cam.get_meta(&"ride_planes")
		cam.near = rp.x
		cam.far = rp.y
	if is_instance_valid(terrain) and terrain.has_method("set_ground_fade"):
		terrain.call("set_ground_fade", 1.0 - fade)
		(terrain as Node3D).visible = not dormant
	if is_instance_valid(scenery):
		# Trees and streets are gone long before this, but the meshes are still
		# being submitted; above the band there is no reason to submit them.
		(scenery as Node3D).visible = not dormant

## The part of the sheet the eye can see from where it is: the cap out to the
## horizon round the point under it, as u0, u1, v0, v1.
##
## Worked out from the camera's direction off the planet's centre in the
## planet's own frame -- the same sum the shader does per pixel -- so the
## window lands where the shader looks for it wherever the chart has got to.
func _patch_window(cam: Camera3D) -> PackedFloat32Array:
	var rel: Vector3 = cam.global_position - Sim.planet_centre
	var dist: float = maxf(rel.length(), 1.0)
	# The horizon of the planet as drawn, which is the shrunken one when a
	# spacecraft is a long way out.
	var rk: float = Sim.PLANET_R * Sim.view_scale
	var ang: float = clampf(acos(clampf(rk / dist, 0.0, 1.0)) * 1.1, PATCH_MIN, PATCH_MAX)
	# The satellite view looking down sees its own footprint, not the horizon:
	# baked out to the horizon, the cap's texels were two kilometres each from
	# three hundred kilometres up and the ground under the view was a smear.
	if cam is SatView and (cam as SatView).tilt < 0.35:
		var vp: Vector2 = cam.get_viewport().get_visible_rect().size
		var aspect: float = vp.x / maxf(vp.y, 1.0)
		var foot: float = (cam as SatView).view_height() * tan(deg_to_rad(cam.fov) * 0.5) \
			* sqrt(1.0 + aspect * aspect) * 1.3
		ang = clampf(foot / Sim.PLANET_R, PATCH_MIN, ang)
	return _window_at(Sim.world_to_planet_dir(rel / dist).normalized(), ang)

## The window `ang` radians either side of `d`, a direction in the planet's
## frame.
##
## Snapped: the span up to the next of a ladder of sizes and the middle to an
## eighth of it, so the same place at the same height asks for the same window
## every time -- which is what lets the picture be kept on disk and found again.
func _window_at(d: Vector3, ang: float) -> PackedFloat32Array:
	ang = PATCH_MIN * pow(PATCH_LADDER, ceilf(log(maxf(ang, PATCH_MIN) / PATCH_MIN) / log(PATCH_LADDER) - 1e-4))
	var north: Vector3 = Sim.PLANET_NORTH
	var home := Vector3.UP
	var east: Vector3 = north.cross(home).normalized()
	var lat: float = asin(clampf(d.dot(north), -1.0, 1.0))
	var lon: float = atan2(d.dot(east), d.dot(home))
	var uc: float = lon / TAU + 0.5
	var vc: float = 0.5 - lat / PI
	var dv: float = ang / PI
	vc = snappedf(vc, dv * 0.25)
	lat = (0.5 - vc) * PI
	# Meridians close up toward the poles, so the same cap spans more of them
	# the further it is from the equator; one with a pole in it spans them all.
	var du := 0.5
	if sin(ang) < cos(lat) * 0.995:
		du = minf(asin(sin(ang) / cos(lat)) / TAU, 0.5)
		uc = snappedf(uc, du * 0.25)
	return PackedFloat32Array([uc - du, uc + du,
		clampf(vc - dv, 0.0, 1.0), clampf(vc + dv, 0.0, 1.0)])

## Bake the window if what is held no longer covers it. One bake in flight at a
## time, and what goes out after it is the newest window wanted meanwhile.
func _want_patch(win: PackedFloat32Array, cache := false) -> void:
	if Sim.native == null or not Sim.native.has_method("body_patch_request"):
		return
	if _patch_win.size() == 4 and not _patch_stale(_patch_win, win):
		return
	if _patch_asked.size() == 4:
		if not _patch_stale(_patch_asked, win):
			return
		_patch_next = win
		_patch_next_cache = cache
		return
	var path := _patch_path(win) if cache else ""
	if path != "" and FileAccess.file_exists(path):
		_patch_asked = win
		_patch_next = PackedFloat32Array()
		_disk_path = path
		_disk_task = WorkerThreadPool.add_task(_read_patch.bind(path), true, "patch read")
		return
	if Sim.native.body_patch_request(PATCH_RES, Sim.PLANET_NORTH,
			win[0], win[1], win[2], win[3]):
		_patch_asked = win
		_patch_save = path
		_patch_next = PackedFloat32Array()

## The file a window's picture is kept in: by the window, the season it was
## painted in (to a twentieth of the year's swing) and the code that painted it.
func _patch_path(win: PackedFloat32Array) -> String:
	if _code_sig == "":
		_code_sig = WorldBake.signature()
	var key := "%s|%d|%.5f,%.5f,%.5f,%.5f|%d" % [_code_sig, PATCH_RES, win[0], win[1], win[2],
		win[3], int(round(Sim.season * 10.0))]
	return "%s/%s.bin" % [PATCH_CACHE, key.sha256_text().substr(0, 24)]

## On a worker: the cached picture, or nothing if it will not read.
func _read_patch(path: String) -> void:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		_disk_buf = PackedByteArray()
		return
	var n: int = f.get_32()
	_disk_buf = f.get_buffer(n)
	f.close()

## On a worker: keep a fresh bake, and no more of them than the budget.
static func _write_patch(path: String, buf: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(PATCH_CACHE)
	var tmp := path + ".part"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_32(buf.size())
	f.store_buffer(buf)
	f.close()
	DirAccess.rename_absolute(tmp, path)
	var d := DirAccess.open(PATCH_CACHE)
	if d == null:
		return
	var files: Array = []
	var total := 0
	for fn in d.get_files():
		if fn.ends_with(".bin"):
			var full := "%s/%s" % [PATCH_CACHE, fn]
			var sz := 0
			var rf := FileAccess.open(full, FileAccess.READ)
			if rf != null:
				sz = rf.get_length()
				rf.close()
			total += sz
			files.append([FileAccess.get_modified_time(full), full, sz])
	if total <= PATCH_CACHE_BYTES:
		return
	files.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	for e in files:
		if total <= PATCH_CACHE_BYTES:
			break
		DirAccess.remove_absolute(String(e[1]))
		total -= int(e[2])

## Whether the picture of a satellite view holding on `d` is on disk.
func on_disk(d: Vector3) -> bool:
	if Sim.native == null or not Sim.native.has_method("body_patch_request"):
		return true
	return FileAccess.file_exists(_patch_path(_window_at(d, FOCUS_PATCH_ANG)))

## Bake the picture of `d` for the disk, on the loading screen: poll
## `warming` (which also takes delivery) until it says no.
func warm(d: Vector3) -> void:
	if _patch_asked.size() == 4 or on_disk(d):
		return
	var win := _window_at(d, FOCUS_PATCH_ANG)
	if Sim.native.body_patch_request(PATCH_RES, Sim.PLANET_NORTH,
			win[0], win[1], win[2], win[3]):
		_patch_asked = win
		_patch_save = _patch_path(win)
		_patch_warm = true

func warming() -> bool:
	_collect_patch()
	return _patch_asked.size() == 4

## Whether the fine picture is up for a satellite view holding on `d` (a
## direction in the planet's frame), or there is nothing that could make one.
func focus_ready(d: Vector3) -> bool:
	if Sim.native == null or not Sim.native.has_method("body_patch_request"):
		return true
	var win := _window_at(d, FOCUS_PATCH_ANG)
	return _patch_win.size() == 4 and not _patch_stale(_patch_win, win)

## Ask for the fine picture of `d` ahead of time -- on the loading screen,
## before anything is looking at it -- and take delivery as it comes.
func prepare_focus(d: Vector3) -> void:
	_collect_patch()
	_want_patch(_window_at(d, FOCUS_PATCH_ANG), true)

## Whether `held` is far enough from `want` to be worth baking again.
func _patch_stale(held: PackedFloat32Array, want: PackedFloat32Array) -> bool:
	var hu: float = held[1] - held[0]
	var hv: float = maxf(held[3] - held[2], 1e-6)
	var wu: float = want[1] - want[0]
	var wv: float = want[3] - want[2]
	var off_u: float = wrapf((want[0] + want[1] - held[0] - held[1]) * 0.5, -0.5, 0.5)
	var off_v: float = (want[2] + want[3] - held[2] - held[3]) * 0.5
	return absf(wu - hu) > hu * PATCH_SLACK or absf(wv - hv) > hv * PATCH_SLACK \
		or absf(off_u) > hu * PATCH_SLACK or absf(off_v) > hv * PATCH_SLACK

## Take delivery of a finished bake and hang it on the window it is of.
func _collect_patch() -> void:
	if _patch_asked.size() != 4 or Sim.native == null:
		return
	var buf: PackedByteArray
	if _disk_task >= 0:
		if not WorkerThreadPool.is_task_completed(_disk_task):
			return
		WorkerThreadPool.wait_for_task_completion(_disk_task)
		_disk_task = -1
		buf = _disk_buf
		_disk_buf = PackedByteArray()
		if buf.size() != _patch_bytes():
			# unreadable: thrown away, and baked again
			DirAccess.remove_absolute(_disk_path)
			var again_w := _patch_asked
			_patch_asked = PackedFloat32Array()
			_want_patch(again_w, true)
			return
	else:
		if not Sim.native.body_patch_ready():
			return
		buf = Sim.native.body_patch_take()
		if _patch_save != "" and buf.size() == _patch_bytes():
			WorkerThreadPool.add_task(_write_patch.bind(_patch_save, buf), false, "patch save")
		_patch_save = ""
		if _patch_warm:
			# for the disk, not for the screen
			_patch_warm = false
			_patch_asked = PackedFloat32Array()
			if _patch_next.size() == 4:
				var nw := _patch_next
				_patch_next = PackedFloat32Array()
				_want_patch(nw, _patch_next_cache)
			return
	var _pt := Sim.prof_at()
	var img := Image.create_from_data(PATCH_RES, PATCH_RES, true,
		Image.FORMAT_RGBA8, buf) if buf.size() == _patch_bytes() else null
	if img != null:
		# Updated in place once there is one: the same size and format every
		# time, so the texture keeps its RID and nothing has to be rebound.
		if _patch_tex == null:
			_patch_tex = ImageTexture.create_from_image(img)
			_mat.set_shader_parameter("patch_tex", _patch_tex)
		else:
			_patch_tex.update(img)
		_patch_win = _patch_asked
		_mat.set_shader_parameter("patch_win", Vector4(_patch_win[0], _patch_win[1],
			_patch_win[2], _patch_win[3]))
		_mat.set_shader_parameter("patch_on", 1.0)
	Sim.prof_end(&"planet.patch", _pt)
	_patch_asked = PackedFloat32Array()
	if _patch_next.size() == 4:
		var again := _patch_next
		_patch_next = PackedFloat32Array()
		_want_patch(again, _patch_next_cache)

## What a baked window comes to with its mips, which is what the extension
## hands back.
func _patch_bytes() -> int:
	var n := 0
	var s := PATCH_RES
	while true:
		n += s * s * 4
		if s == 1:
			break
		s = maxi(s >> 1, 1)
	return n
