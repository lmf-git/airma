class_name Lakes
extends Node3D
## The standing water above the sea: the lakes and inland seas the extension
## finds on the planet (see `sphere::Lake`), drawn as a surface over each basin.
##
## The ground under them is already a basin -- the extension takes it out of
## the field -- so all this draws is the water's top: a flat disc over the rim
## at the lake's level, following the curve of the planet. Where the land
## stands above it the land hides it, so the shore is wherever the ground
## crosses the surface, inlets and islands and all, and not a circle.

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

// Dithered out with the ground it belongs to, like the sea, while the planet
// body takes over from the terrain.
uniform float ground_fade = 1.0;
uniform float t = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying vec3 wpos;
varying float rim;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// how far out to the rim this vertex is, 0 in the middle and 1 at it
	rim = UV.y;
}

void fragment() {
	if (ground_fade < 0.999) {
		float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy,
			vec2(0.06711056, 0.00583715))));
		if (ground_fade <= ign) {
			discard;
		}
	}
	// How much water lies between this point of the surface and the bed behind
	// it, along the line of sight: clear in the shallows, dark where it is deep.
	float thick = 1.0e4;
	float sd = texture(depth_tex, SCREEN_UV).r;
	if (sd > 0.0) {
		vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, sd, 1.0);
		thick = max(length(vp.xyz / vp.w) - length(VERTEX), 0.0);
	}
	float deep = clamp(thick / 35.0, 0.0, 1.0);
	// A little wind on it, let go where a pixel covers too much of it to show
	// anything but sparkle.
	vec2 p = wpos.xz;
	float fp = max(length(dFdx(p)), length(dFdy(p)));
	float keep = 1.0 - smoothstep(1.5, 6.0, fp);
	vec2 g = vec2(sin(p.x * 0.21 + t * 1.3) + sin(p.y * 0.17 - t * 0.9),
		sin(p.y * 0.23 + t * 1.1) + sin(p.x * 0.19 + t * 0.7)) * 0.035 * keep;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-g.x, 1.0, -g.y)), 0.0)).xyz);
	ALBEDO = mix(vec3(0.10, 0.21, 0.20), vec3(0.02, 0.07, 0.11), deep);
	ROUGHNESS = 0.07;
	METALLIC = 0.35;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	// Faded out at the very rim: anywhere the land between two of the rim's
	// samples dips under the surface, the water ends in the open rather than
	// in a wall.
	ALPHA = clamp(mix(0.30, 0.94, sqrt(deep)) + fres * 0.3, 0.0, 0.97)
		* (1.0 - smoothstep(0.94, 1.0, rim));
}
"""

## The planet, for how far the hand-over from the ground has got.
var planet: Planet = null
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0

func _ready() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	# After the sea, which sorts at -8, and before anything at the surface.
	_mat.render_priority = -7
	_mi = MeshInstance3D.new()
	_mi.name = "LakeWater"
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	Sim.lakes_changed.connect(_rebuild)
	_rebuild()

func _process(delta: float) -> void:
	_t += delta
	_mat.set_shader_parameter("t", _t)
	if is_instance_valid(planet):
		_mat.set_shader_parameter("ground_fade", 1.0 - planet.fade)
		visible = not planet.dormant

## One mesh for every lake round the chart, laid on the curve of the planet in
## the chart's own numbers. Built again whenever the chart moves.
func _rebuild() -> void:
	var lk: PackedFloat32Array = Sim.lakes
	var n_lakes: int = lk.size() >> 2
	if n_lakes == 0:
		_mi.mesh = null
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for li in n_lakes:
		var b: int = li * 4
		var cx: float = lk[b]
		var cz: float = lk[b + 1]
		var r: float = lk[b + 2]
		var flat_y: float = Sim.WATER_LEVEL + lk[b + 3]
		# Fine enough that the flat triangles stay on the curve -- a sagitta of a
		# few centimetres -- and that the rim reads round.
		var rings: int = clampi(int(r / 700.0), 5, 32)
		var spokes: int = clampi(int(r / 160.0), 24, 128)
		var base: int = verts.size()
		verts.append(Vector3(cx, flat_y - Sim.planet_drop(cx, cz), cz))
		norms.append(Vector3.UP)
		uvs.append(Vector2(0.0, 0.0))
		for ri in range(1, rings + 1):
			var rr: float = r * float(ri) / float(rings)
			for si in spokes:
				var a: float = TAU * float(si) / float(spokes)
				var x: float = cx + cos(a) * rr
				var z: float = cz + sin(a) * rr
				verts.append(Vector3(x, flat_y - Sim.planet_drop(x, z), z))
				norms.append(Vector3.UP)
				uvs.append(Vector2(0.0, float(ri) / float(rings)))
		# the fan round the middle, then the rings out to the rim (drawn from
		# both sides, so a man under the surface sees it too)
		for si in spokes:
			var s2: int = (si + 1) % spokes
			idx.append_array(PackedInt32Array([base, base + 1 + s2, base + 1 + si]))
		for ri in range(1, rings):
			var in0: int = base + 1 + (ri - 1) * spokes
			var out0: int = base + 1 + ri * spokes
			for si in spokes:
				var s2: int = (si + 1) % spokes
				idx.append_array(PackedInt32Array([in0 + si, in0 + s2, out0 + s2]))
				idx.append_array(PackedInt32Array([in0 + si, out0 + s2, out0 + si]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var me := ArrayMesh.new()
	me.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mi.mesh = me
