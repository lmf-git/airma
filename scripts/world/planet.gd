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
uniform sampler2D relief : source_color, filter_linear, repeat_enable;
uniform float map_half = 600000.0;
// 0 hides the body, 1 draws it. The ground is dithering out over the same band.
uniform float fade = 0.0;
// The planet's frame: where its centre is, which way its north lies, and which
// way the middle of the theatre lies. Longitude is measured from the theatre,
// so the world lands on the planet where the world actually is.
uniform vec3 centre = vec3(0.0);
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
	vec3 u = normalize(wpos - centre);
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
	ALBEDO = texture(relief, uv).rgb;
	ROUGHNESS = 0.94;
	METALLIC = 0.0;
	ALPHA = fade;
}
"""

## The generated planet, and the sheet baked from it.
##
## Equirectangular, and read by both the body and the tactical globe, so the
## planet you see from orbit and the planet you see on the map are the same
## planet. One texel is 39 km, which is right for a body seen from at least
## thirty-eight kilometres up; the theatre's own detail comes from the map's
## detail sheet and from the terrain itself.
const SHEET_W := 1024
const SHEET_H := 512

var terrain_gen: PlanetTerrain
var sheet: ImageTexture
var _mi: MeshInstance3D
var _mat: ShaderMaterial
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
	return ImageTexture.create_from_image(Image.create_from_data(
		SHEET_W, SHEET_H, false, Image.FORMAT_RGB8, buf))

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
	_mi = MeshInstance3D.new()
	_mi.name = "PlanetBody"
	_mi.mesh = _sphere()
	_mi.material_override = _mat
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

func _sphere() -> ArrayMesh:
	var rings := _ring_angles()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = Sim.PLANET_R
	for i in range(rings.size() - 1):
		var t0: float = rings[i]
		var t1: float = rings[i + 1]
		for j in SEGS:
			var p0: float = TAU * float(j) / float(SEGS)
			var p1: float = TAU * float(j + 1) / float(SEGS)
			var a := _on(t0, p0, r)
			var b := _on(t0, p1, r)
			var c := _on(t1, p1, r)
			var d := _on(t1, p0, r)
			# The pole rings are a fan, not a strip: two of the four corners are
			# the same point and the degenerate triangle is not worth emitting.
			if i > 0:
				_tri(st, a, b, c)
			_tri(st, a, c, d)
	# No tangents: there are no UVs to make them from and nothing sampling a
	# normal map. Asking for them is an error, not a no-op.
	return st.commit()

func _on(theta: float, phi: float, r: float) -> Vector3:
	var s := sin(theta)
	return Vector3(s * cos(phi) * r, cos(theta) * r, s * sin(phi) * r)

## Outward normals, taken from the sphere itself rather than the face, so the
## shading is smooth however coarse the rings get.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal((v as Vector3).normalized())
		st.add_vertex(v)

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
	# Only once there is something out there to see. Left at 2600 km from the
	# ground the far plane would be paying for the whole cap on every frame of
	# a landing circuit.
	cam.far = lerpf(FAR_LO, FAR_HI, fade)
	cam.near = clampf(cam.far / NEAR_RATIO, NEAR_LO, NEAR_MAX)
	if is_instance_valid(terrain) and terrain.has_method("set_ground_fade"):
		terrain.call("set_ground_fade", 1.0 - fade)
		(terrain as Node3D).visible = not dormant
	if is_instance_valid(scenery):
		# Trees and streets are gone long before this, but the meshes are still
		# being submitted; above the band there is no reason to submit them.
		(scenery as Node3D).visible = not dormant
