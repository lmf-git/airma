class_name GVeil
extends ColorRect
## Grey-out and red-out. The pilot's field of view closes in and the colour
## drains as +Gz is held past tolerance; negative g fills it with blood instead.
## Drawn under the HUD so the instruments stay legible while the world goes.

var jet: Node = null            # whoever is pulling the g
var debug_strain := -1.0        # >= 0 pins the effect, for looking at it

const SRC := """
shader_type canvas_item;
uniform float strain : hint_range(0.0, 1.0) = 0.0;
uniform float redout : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	// an ellipse, because the field of view is wider than it is tall
	vec2 d = (UV - vec2(0.5)) * vec2(1.0, 1.55);
	float r = length(d) * 2.0;
	// the clear aperture closes from well outside the frame to a pinhole
	float inner = mix(2.1, 0.02, strain);
	float v = smoothstep(inner, inner - 0.55, r);
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	// colour drains toward a dim sepia before it goes altogether
	vec3 drained = vec3(grey) * vec3(0.62, 0.52, 0.40);
	vec3 col = mix(c, drained, strain * 0.85);
	col *= mix(1.0, v, strain);
	// red-out: the eyeballs fill from the outside in
	float rv = smoothstep(mix(2.1, 0.35, redout), mix(2.1, 0.35, redout) - 0.7, r);
	vec3 blood = mix(vec3(dot(col, vec3(0.33))) * vec3(0.55, 0.05, 0.04),
		col, rv);
	col = mix(col, blood, redout);
	COLOR = vec4(col, 1.0);
}
"""

func _ready() -> void:
	name = "GVeil"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	var sh := Shader.new()
	sh.code = SRC
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
	color = Color.WHITE
	visible = false

## A Control parented straight to a CanvasLayer has nothing for its anchors to
## resolve against, so it ends up zero-sized and draws nothing at all. Setting
## the offsets along with the anchors resolves the rect properly; assigning the
## size by hand on top of full rect anchors is what Godot warns about, because
## the anchors overwrite it after _ready anyway.
func _fit() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_dt: float) -> void:
	if debug_strain >= 0.0:
		visible = true
		material.set_shader_parameter("strain", debug_strain)
		material.set_shader_parameter("redout", 0.0)
		return
	if jet == null or not is_instance_valid(jet):
		visible = false
		return
	var st: float = jet.g_strain
	var rd: float = jet.g_red
	if st < 0.002 and rd < 0.002:
		visible = false
		return
	visible = true
	material.set_shader_parameter("strain", st)
	material.set_shader_parameter("redout", rd)
