class_name VisionFx
extends RefCounted
## Full-screen effects over the view: the underwater tint, night vision, the
## submarine's sonar picture and the flash of a nuclear burst.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

const VIEW_NVG := 1
const VIEW_SONAR := 2
## What it looks like with your head under the sea. Drawn under everything else
## on the interface layer, so the instruments stay readable: the water is in
## front of the world, not in front of the panel.
var _uw: ColorRect = null
var _uw_mat: ShaderMaterial = null
var _uw_t := 0.0
var vision := World.VIEW_PLAIN
## The flash. A warhead of that size whites out everything that can see it, and
## it whites out the *screen*, not a patch of sky — you cannot look away from it
## in time and neither can the aeroplane.
var _flash: ColorRect = null
var _flash_mat: ShaderMaterial = null
var _flash_t := 0.0
var _flash_span := 0.0


func _init(w: World) -> void:
	world = w


func build_underwater(ui: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float submerged : hint_range(0.0, 1.0) = 0.0;
uniform float murk : hint_range(0.0, 1.0) = 0.0;
uniform float t = 0.0;
uniform vec3 tint = vec3(0.06, 0.26, 0.34);

void fragment() {
	vec2 uv = SCREEN_UV;
	// the surface moving overhead, seen through the water column
	float wob = 0.0016 + 0.0022 * murk;
	uv.x += sin(uv.y * 34.0 + t * 1.7) * wob * submerged;
	uv.y += cos(uv.x * 41.0 + t * 1.3) * wob * submerged;
	vec3 c = texture(screen, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	// green-blue absorbs last: red goes first, and it goes quickly
	vec3 absorbed = vec3(0.28, 0.72, 0.86);
	c *= mix(vec3(1.0), absorbed, submerged * (0.70 + 0.30 * murk));
	c = mix(c, tint, submerged * (0.42 + 0.55 * murk));
	// it gets darker and closer in as you go down
	float d = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - submerged * murk * 0.55 * smoothstep(0.15, 0.85, d);
	COLOR = vec4(c, submerged);
}
"""
	_uw_mat = ShaderMaterial.new()
	_uw_mat.shader = sh
	_uw = ColorRect.new()
	_uw.name = "Underwater"
	_uw.material = _uw_mat
	_uw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_uw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_uw.visible = false
	ui.add_child(_uw)


## How far the eye is under the surface, and therefore how much of it to draw.
func update_underwater(delta: float) -> void:
	if _uw == null:
		return
	var eye := world.get_viewport().get_camera_3d()
	if eye == null:
		_uw.visible = false
		return
	var under: float = Sim.sea_surface(eye.global_position.x,
		eye.global_position.z) - eye.global_position.y
	# eased across the surface, so breaking it is not a hard cut
	var amount: float = clampf(under / 1.2, 0.0, 1.0)
	_uw.visible = amount > 0.001
	if not _uw.visible:
		return
	_uw_t += delta
	_uw_mat.set_shader_parameter("submerged", amount)
	# Fully murky by twelve metres down, not fifty-five. Water is not a window:
	# a few metres of it swallows the horizon, and at the old rate you could
	# still see the far side of a bay from the bottom of it.
	_uw_mat.set_shader_parameter("murk", clampf(under / 12.0, 0.0, 1.0))
	_uw_mat.set_shader_parameter("t", _uw_t)


func build_nightvision(ui: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float t = 0.0;
// A tube's whole job is that it shows you a moonlit hillside. At 3.4 the
// amplifier could not lift a night scene off the floor -- the luminance of
// unlit ground at night is a hundredth of full scale, which came out as a
// hundredth of the way up the curve, and the answer was black.
uniform float gain = 14.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	// what the tube sees is brightness, not colour
	float l = dot(c, vec3(0.30, 0.59, 0.11));
	// amplified, and it saturates: a tube cannot show you a bright sky and a
	// dark hillside at once
	// lifted before it is amplified, so the shadows come up rather than being
	// crushed against nothing
	// The exponent does far more work here than the gain does.
	//
	// Unlit ground at night sits around a hundredth of full scale, and at 0.72
	// that came out of the curve at a fifth of the way up -- dark grey on a
	// black field, which is why the country was not really there. The gain
	// cannot fix it: multiplying a number that has already been crushed toward
	// zero just moves the same crushed picture up a little. Lifting the curve
	// instead pulls the bottom decade of the scene up into the middle of the
	// range, which is exactly what an image intensifier does.
	// A floor under the darkest part of the scene.
	//
	// Water is a smooth specular surface, so after dark it reflects nothing and
	// is genuinely black -- and no amount of amplification turns black into a
	// picture. A real tube never shows black either: it shows the noise floor
	// of the tube itself, which is what tells you there is a surface there at
	// all. Lifting the bottom of the scale gives the sea back its surface and
	// leaves anything already lit exactly where it was.
	float lit = max(l, 0.0016);
	float amp = 1.0 - exp(-pow(lit, 0.45) * gain);
	// grain, which is the photons arriving one at a time
	float g = h21(SCREEN_UV * vec2(1920.0, 1080.0) + vec2(t * 71.0, t * 37.0));
	amp = clamp(amp + (g - 0.5) * 0.085, 0.0, 1.0);
	// scan lines and the circular field of the eyepiece
	float scan = 0.94 + 0.06 * sin(SCREEN_UV.y * 1400.0);
	float d = distance(SCREEN_UV, vec2(0.5)) * 1.9;
	float tube = 1.0 - smoothstep(0.72, 1.05, d);
	vec3 phosphor = vec3(0.22, 1.0, 0.34);
	COLOR = vec4(phosphor * amp * scan * tube, 1.0);
}
"""
	world._nvg_mat = ShaderMaterial.new()
	world._nvg_mat.shader = sh
	world._nvg = ColorRect.new()
	world._nvg.name = "NightVision"
	world._nvg.material = world._nvg_mat
	world._nvg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world._nvg.set_anchors_preset(Control.PRESET_FULL_RECT)
	world._nvg.visible = false
	ui.add_child(world._nvg)
	_build_sonar(ui)


func _build_sonar(ui: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float t = 0.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.30, 0.59, 0.11));
	// Anything the wireframe drew is a return; the empty space between the
	// lines is water, and water comes back as nothing.
	float ret = clamp(pow(l, 0.75) * 1.6, 0.0, 1.0);
	float n = h21(SCREEN_UV * vec2(430.0, 270.0) + vec2(t * 3.1, t)) - 0.5;
	ret = clamp(ret + n * 0.22, 0.0, 1.0);
	// the sweep, travelling down the picture
	float ping = fract(t * 0.30);
	ret = max(ret, smoothstep(0.05, 0.0, abs(SCREEN_UV.y - ping)) * 0.40);
	vec3 outc = mix(vec3(0.008, 0.035, 0.045), vec3(0.30, 1.0, 0.82), ret);
	outc += vec3(0.0, 0.28, 0.24) * pow(ret, 5.0);
	// range rings struck from the boat, which is at the bottom of the picture
	float rr = abs(fract(length((SCREEN_UV - vec2(0.5, 1.0))
		* vec2(1.0, 1.6)) * 4.0) - 0.5);
	outc += vec3(0.0, 0.14, 0.12) * smoothstep(0.47, 0.50, rr);
	float scan = 0.93 + 0.07 * sin(SCREEN_UV.y * 900.0);
	COLOR = vec4(outc * scan, 1.0);
}
"""
	world._sonar_mat = ShaderMaterial.new()
	world._sonar_mat.shader = sh
	world._sonar = ColorRect.new()
	world._sonar.name = "Sonar"
	world._sonar.material = world._sonar_mat
	world._sonar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world._sonar.set_anchors_preset(Control.PRESET_FULL_RECT)
	world._sonar.visible = false
	ui.add_child(world._sonar)


## Sonar belongs to a boat that dives. A tank commander and a pilot have no set
## to switch to, so the cycle is two long for them and three for a submariner.
func _has_sonar() -> bool:
	return is_instance_valid(world.ship) and world.ship.has_method("can_dive") \
		and bool(world.ship.call("can_dive"))


func toggle_nvg() -> void:
	vision = (vision + 1) % (3 if _has_sonar() else 2)
	world.nvg_on = vision == VIEW_NVG
	if world._nvg:
		world._nvg.visible = world.nvg_on
	if world._sonar:
		world._sonar.visible = vision == VIEW_SONAR
	# Sonar is not a picture of anything: it is a return off a surface, and the
	# surface is all it can tell you about. Drawing the scene as wireframe is
	# the closest a rasteriser gets to that -- the shape of the bottom, the hull
	# of a ship, and nothing in between.
	var vp := world.get_viewport()
	if vp != null:
		vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if vision == VIEW_SONAR \
			else Viewport.DEBUG_DRAW_DISABLED
	Sim.report(["unaided", "night vision", "sonar"][vision], Sim.Ev.INFO)


func build_flash(ui: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float warm : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	// blown out white in the middle, going through the colour of the fireball
	// at the edges as the eye starts to recover
	float d = distance(SCREEN_UV, vec2(0.5)) * 1.4;
	vec3 hot = mix(vec3(1.0), vec3(1.0, 0.72, 0.42), warm * d);
	COLOR = vec4(hot, clamp(amount * (1.15 - d * 0.35), 0.0, 1.0));
}
"""
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = sh
	_flash = ColorRect.new()
	_flash.name = "NukeFlash"
	_flash.material = _flash_mat
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.visible = false
	ui.add_child(_flash)


## Called when a warhead goes off. `lethal` is its radius, and the flash is
## seen a very long way beyond that — being outside the blast is not the same
## as not being blinded by it.
func nuke_flash(at: Vector3, lethal: float) -> void:
	var eye := world.get_viewport().get_camera_3d()
	if eye == null or _flash == null:
		return
	var d: float = eye.global_position.distance_to(at)
	# visible out to a couple of hundred times the lethal radius
	var reach: float = lethal * 200.0
	if d > reach:
		return
	# no falloff worth the name up close, then an inverse square out to the edge
	var near: float = clampf(1.0 - d / reach, 0.0, 1.0)
	var bite: float = clampf(pow(near, 0.45), 0.0, 1.0)
	# behind you it is the sky lighting up, not the fireball itself
	if eye.is_position_behind(at):
		bite *= 0.55
	_flash_span = maxf(_flash_span, 1.6 + bite * 5.5)
	_flash_t = maxf(_flash_t, _flash_span)
	_flash.visible = true


func update_flash(delta: float) -> void:
	if _flash == null or not _flash.visible:
		return
	_flash_t = maxf(_flash_t - delta, 0.0)
	if _flash_t <= 0.0:
		_flash.visible = false
		_flash_span = 0.0
		return
	var f: float = _flash_t / maxf(_flash_span, 0.01)
	# a hard white for the first instant, then the eye recovering over seconds
	_flash_mat.set_shader_parameter("amount", pow(f, 1.7))
	_flash_mat.set_shader_parameter("warm", clampf(1.0 - f * 1.4, 0.0, 1.0))
