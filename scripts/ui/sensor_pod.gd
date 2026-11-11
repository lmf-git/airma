class_name SensorPod
extends Control
## Targeting pod page. ALT + right click opens it, the mouse slews the head, and
## CTRL+T either point-tracks whatever is under the crosshair or ground
## stabilises on the spot it is looking at.

enum { SLEW, AREA, POINT }

const SIZE := Vector2(360, 360)

## What the sensor is bolted to — an aeroplane, a ship, a tank, anything.
##
## This used to be two properties: `jet` for an aeroplane and `host` for
## everything else, with an accessor that returned whichever was set. That is
## why the slant range readout reached straight for `jet` and threw the moment a
## tank crew opened the sight: there were two names for one thing and half the
## code only knew about one of them. A sensor does not care what it is mounted
## on, so neither does this.
var platform: Node3D = null
var mode := SLEW
var area_point := Vector3.ZERO
var tracked: Node3D = null
var yaw := 0.0                      # pod head angles, relative to the airframe
var pitch := -0.35
var zoom_step := 1
var active := false
var fullscreen := false

const ZOOMS := [26.0, 9.0, 3.2, 1.2]

var _vp: SubViewport
var _cam: Camera3D
var _tex: TextureRect
var _font: Font
var _t := 0.0
var diag := false
var _diag_prev := Vector3.INF
var shake_worst := 0.0
var shake_sum := 0.0
var shake_n := 0
var _marker: LaserSpot
var lasing := false
## Set when the laser comes on, so the spot is selected once rather than forced
## on the aeroplane every frame -- which is what stopped T reaching anything
## else for as long as the laser was lit.
var _select_spot := false
var _beam: MeshInstance3D

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	visible = false

	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE)
	_vp.transparent_bg = false
	# Drawn only while the page is up: see `_render_when_up`.
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.own_world_3d = false
	_vp.handle_input_locally = false
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)

	_cam = Camera3D.new()
	_cam.far = 45000.0
	_cam.near = 0.5
	_cam.fov = ZOOMS[zoom_step]
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_vp.add_child(_cam)
	_cam.current = true

	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.size = SIZE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.material = _flir_material()
	# A Control paints its own _draw() BEFORE its children, so the camera image
	# was going down on top of the symbology and the pod came up looking like a
	# window with nothing on the glass. Push the picture behind the overlay.
	_tex.show_behind_parent = true
	add_child(_tex)

## Sensor channels. One shader with a mode switch rather than four materials,
## because they all start from the same picture and differ only in how the
## luminance is mapped.
const CH_TV := 0
const CH_NIGHT := 1
const CH_WHOT := 2
const CH_BHOT := 3
const CH_SONAR := 4
const CHANNEL_NAMES := ["TV", "NIGHT", "WHOT", "BHOT", "SONAR"]
var channel := CH_WHOT

func _flir_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.16;
uniform int channel = 2;      // 0 TV, 1 night, 2 white hot, 3 black hot, 4 sonar
uniform float grain_t = 0.0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.30, 0.59, 0.11));
	vec3 outc;
	float vig = smoothstep(1.05, 0.35, length(UV - vec2(0.5)));
	if (channel == 0) {
		// direct view: the daylight picture, lightly graded
		outc = c.rgb * 1.05;
		vig = mix(1.0, vig, 0.45);
	} else if (channel == 1) {
		// image intensifier: green, bloomed at the top end, and noisy
		float g = clamp(pow(l, 0.55) * 1.9, 0.0, 1.0);
		float n = h21(UV * vec2(720.0, 400.0) + vec2(grain_t, grain_t * 1.7)) - 0.5;
		g = clamp(g + n * 0.13, 0.0, 1.0);
		outc = mix(vec3(0.01, 0.05, 0.02), vec3(0.55, 1.0, 0.60), g);
		outc += vec3(0.0, 0.35, 0.10) * pow(g, 6.0);   // blooming highlights
	} else if (channel == 4) {
		// Active sonar. Not a photograph of anything: a sonar display shows how
		// strongly a bearing came back, painted in the one colour these have
		// always been, and it hears nothing at all above the waterline.
		//
		// Sky and open water return almost nothing, so both go dark. What is
		// left is the solid stuff -- a hull, the bottom, a cliff -- and it
		// arrives buried in noise, which is most of what makes a sonar picture
		// look like a sonar picture rather than a green photograph.
		float sat2 = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
		float water = smoothstep(0.02, 0.20, c.b - c.r);
		float ret = clamp(pow(l, 0.9) * (1.0 - water) * (0.35 + 0.9 * sat2),
			0.0, 1.0);
		float n2 = h21(UV * vec2(430.0, 270.0)
			+ vec2(grain_t * 3.1, grain_t)) - 0.5;
		ret = clamp(ret + n2 * 0.30, 0.0, 1.0);
		// the sweep: a band travelling down the screen, lighting what it passes
		float ping = fract(grain_t * 0.30);
		float band = smoothstep(0.055, 0.0, abs(UV.y - ping));
		ret = max(ret, band * 0.45);
		outc = mix(vec3(0.010, 0.040, 0.050), vec3(0.32, 1.0, 0.84), ret);
		outc += vec3(0.0, 0.30, 0.26) * pow(ret, 5.0);
		// range rings, struck from the boat at the bottom of the picture
		float rr = abs(fract(length((UV - vec2(0.5, 1.0)) * vec2(1.0, 1.6))
			* 4.0) - 0.5);
		outc += vec3(0.0, 0.15, 0.13) * smoothstep(0.47, 0.50, rr);
	} else {
		// Thermal, and it has to be a guess at *temperature* rather than a
		// greyscale of the daylight picture. Ramping raw luminance made the sky
		// and the clouds the hottest things on screen — hotter than an engine
		// plume, three times the aeroplane — so white hot looked like a
		// photograph and black hot looked like its negative. Inverting it was
		// arithmetically perfect and told you nothing.
		//
		// Without a temperature buffer the scene still says a good deal: blue
		// dominance is sky and water and both are cold, bright and desaturated
		// is cloud, and red dominance at brightness is something burning.
		float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
		float sky = smoothstep(0.03, 0.22, c.b - c.r);
		float cloudy = smoothstep(0.72, 0.95, l) * (1.0 - smoothstep(0.02, 0.20, sat));
		float cold = clamp(sky + cloudy, 0.0, 1.0);
		float hot = smoothstep(0.12, 0.45, c.r - c.b) * smoothstep(0.30, 0.75, l);
		float t = clamp(pow(l, 0.75), 0.0, 1.0);
		t = mix(t, 0.05, cold);
		t = max(t, hot);
		if (channel == 3) { t = 1.0 - t; }
		outc = vec3(t);
	}
	float scan = 1.0 - scan_strength * step(0.5, fract(UV.y * 190.0));
	COLOR = vec4(outc * scan * vig, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("channel", channel)
	return m

## Whether the thing carrying the pod has a sonar to show: a boat that dives.
func _has_sonar() -> bool:
	return is_instance_valid(platform) and platform.has_method("can_dive") \
		and bool(platform.call("can_dive"))

## Step through the sensor channels.
func cycle_channel() -> void:
	# Sonar is only offered to something that can use it. On an aeroplane it is
	# a channel that shows nothing, and cycling past it every time is worse than
	# not having it.
	var top: int = CHANNEL_NAMES.size() if _has_sonar() else CH_SONAR
	channel = (channel + 1) % top
	if _tex != null and _tex.material != null:
		(_tex.material as ShaderMaterial).set_shader_parameter("channel", channel)
	queue_redraw()

# --------------------------------------------------------------------------
## Blow the pod page up to fill the screen: this is the gunner's station.
func set_fullscreen(on: bool) -> void:
	fullscreen = on
	var want: Vector2 = get_viewport_rect().size if on else SIZE
	custom_minimum_size = want
	size = want
	if on:
		position = Vector2.ZERO
	# The picture a sensor makes, not the screen's: full screen it is drawn at
	# no more than 1280 across and stretched. It was rendered at the window's
	# own size with 2x multisampling -- a second full-resolution frame of the
	# whole world, every frame -- and a thermal picture with grain laid over
	# it does not show the difference.
	var px: Vector2 = want
	if px.x > 1280.0:
		px *= 1280.0 / px.x
	_vp.size = Vector2i(px)
	_tex.size = want
	queue_redraw()

## The second camera renders the whole world, sky and cloud and all. It was
## left rendering every frame whether the page was up or not -- a second view
## of the world drawn into nothing for the whole of every sortie.
func _render_when_up() -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active \
			else SubViewport.UPDATE_DISABLED

## CTRL is the designate modifier while the page is up, not the throttle: see
## `Sim.sensor_keys`. Kept by visibility so every way of opening or closing it
## counts.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		Sim.sensor_keys = is_visible_in_tree()

func _exit_tree() -> void:
	Sim.sensor_keys = false

func toggle() -> void:
	active = not active
	visible = active
	_render_when_up()
	# Coming back to the page keeps whatever the pod was holding. Resetting to
	# SLEW on every activation threw away a point track the moment you looked
	# away from the sensor page, which is the one thing a track is for.
	if active and platform != null and mode == SLEW and not is_instance_valid(tracked):
		yaw = 0.0
		pitch = -0.35
	if not active:
		_stow()

func slew(rel: Vector2) -> void:
	if not active:
		return
	# Azimuth goes all the way round, because a pod head does.
	#
	# It was clamped to +/-137 degrees, which is a stop the hardware does not
	# have: the head is a ball on a roll gimbal and it can look anywhere the
	# airframe is not in the way. The stop meant anything behind you could be
	# point-tracked -- the ship sensor sets `yaw` directly and thinks nothing of
	# it -- and could not be slewed to by hand, so a target the sensor was
	# perfectly capable of holding simply could not be reached with the mouse.
	# Elevation is still clamped, because that one is real: the pod is under the
	# belly and cannot see up through the aeroplane.
	# Scaled to what you can see, not fixed. The head moved 0.0022 rad per unit
	# of mouse whatever the zoom was — so at the narrowest field, which is 1.2
	# degrees against the widest 26, the same flick of the wrist threw the
	# picture twenty-two times further across the screen. Zoomed right in it was
	# unusable: the target jumped from one edge to the other and there was no
	# way to put the crosshair on anything.
	#
	# Tying the gain to the live field of view keeps the movement ON SCREEN
	# constant, which is what the hand is actually judging. The floor stops it
	# becoming so fine at full zoom that slewing anywhere takes all day.
	var fov: float = _cam.fov if is_instance_valid(_cam) else ZOOMS[zoom_step]
	var gain: float = 0.0022 * clampf(fov / ZOOMS[0], 0.05, 1.0)
	# Holding a piece of ground, the hand moves the piece of ground. The track
	# stays a track: the head goes on being stabilised on a point, and that
	# point is walked across the country under the crosshair. Dropping to a
	# free slew the moment the mouse moved meant every small correction threw
	# the stabilisation away, with the aeroplane banking underneath.
	if mode == AREA:
		var look: Vector3 = _aim_dir()
		var frame := Basis.looking_at(look, Vector3.UP if absf(look.y) < 0.98 else Vector3.FORWARD)
		var moved: Vector3 = (frame * (Basis(Vector3.UP, -rel.x * gain)
			* Basis(Vector3.RIGHT, -rel.y * gain) * Vector3(0, 0, -1))).normalized()
		var hit0: Vector3 = _ground_hit(_head_origin(), moved)
		if hit0 != Vector3.INF:
			area_point = hit0
			if _marker != null and is_instance_valid(_marker):
				_marker.global_position = hit0
			return
	# Coming off a track, the hand takes over from where the head IS. The slew
	# angles are the gimbal's own, and while the head was holding a point they
	# were not being used -- so they still said wherever it was last moved by
	# hand, and the first touch of the mouse threw the picture across the
	# country to there.
	if mode != SLEW:
		_sync_head()
	yaw = wrapf(yaw - rel.x * gain, -PI, PI)
	pitch = clampf(pitch - rel.y * gain, -1.5, 0.35)
	mode = SLEW
	tracked = null

## Set the gimbal angles to wherever the head is looking right now, so that
## letting go of a track leaves it looking at the same place.
func _sync_head() -> void:
	if platform == null or not is_instance_valid(platform):
		return
	var d: Vector3 = _mount_xf(platform).basis.orthonormalized().inverse() * _aim_dir()
	if d.length() < 0.5:
		return
	yaw = atan2(-d.x, -d.z)
	pitch = clampf(asin(clampf(d.y, -1.0, 1.0)), -1.5, 0.35)

func zoom(dir: int) -> void:
	zoom_step = clampi(zoom_step + dir, 0, ZOOMS.size() - 1)

## CTRL+T: point track what is under the crosshair, otherwise ground stabilise.
## The aeroplane, when it IS an aeroplane. Anything that only makes sense on one
## — the bomb fall line, the pylon the pod hangs from, the radar target — asks
## for this and gets null in a tank.
## anything at all, point or area.
func plane() -> Aircraft:
	return platform as Aircraft if is_instance_valid(platform) else null

## Hand a contact or a place to whatever is holding the sensor. An aeroplane
## keeps it as its radar target; a ship keeps it as the thing its tubes and its
## battery are laid on.
func _hand_over(t: Node3D) -> void:
	var c := platform
	if c == null:
		return
	if c is Ship:
		(c as Ship).ai_target = t
	elif c is Tank:
		# A tank already has a fire mission slot -- the one the map view writes
		# to. Lasing from the commander's sight lays the piece on the spot,
		# which is the whole point of having the sight on an artillery vehicle.
		var tk := c as Tank
		var w: Vector3 = t.global_position
		tk.map_target = Vector3(w.x, Sim.height_at(w.x, w.z), w.z)
	elif plane() != null:
		plane().target = t

## CTRL+T from the keyboard. Takes what is under the crosshair; pressed again
## with a track held and nothing new under it, lets the track go.
##
## There was no letting go. CTRL+T only ever took something, and slewing an
## area track walks the held point rather than freeing the head -- so a sight
## that started on an area track, which the AC-130 support does, was locked
## on for the whole time it was on station.
func toggle_track() -> void:
	if not active or platform == null:
		return
	if mode != SLEW:
		var under: Node3D = _under_crosshair()
		if under == null or under == tracked:
			release()
			return
	designate()

## Back to a free slew, looking where the track was.
func release() -> void:
	if mode == SLEW:
		return
	_sync_head()
	mode = SLEW
	tracked = null
	if _marker != null and is_instance_valid(_marker):
		_marker.on = false
		_marker.lasing = false
		_marker.visible = false
	var pl := plane()
	if pl != null and pl.target == _marker:
		pl.target = null
	elif platform is Ship and (platform as Ship).ai_target == _marker:
		(platform as Ship).ai_target = null
	Sim.report("track released — slewing", Sim.Ev.INFO)

## The hostile thing nearest the middle of the picture that `designate` would
## take, without taking it.
func _under_crosshair() -> Node3D:
	var origin := _head_origin()
	var dir := _aim_dir()
	var fov_now: float = deg_to_rad(_cam.fov if is_instance_valid(_cam) else ZOOMS[zoom_step])
	var best_ang: float = minf(deg_to_rad(1.5), fov_now / 12.0)
	var my_team: int = int(platform.team) if ("team" in platform) else -1
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == platform or n.is_in_group("no_lock"):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if ("team" in n) and int(n.team) == my_team:
			continue
		var to: Vector3 = (n as Node3D).global_position - origin
		if to.length() > 26000.0:
			continue
		var a := dir.angle_to(to)
		if a < best_ang:
			best_ang = a
			best = n as Node3D
	return best

func designate() -> void:
	if not active or platform == null:
		return
	var origin := _head_origin()
	var dir := _aim_dir()
	var best: Node3D = null
	# How near the crosshair a thing has to be to be taken: a twelfth of the
	# picture, and never more than a degree and a half. It was a flat 2.6
	# degrees, which from four kilometres is a circle a hundred and eighty
	# metres across -- so asking for a piece of ground anywhere near a vehicle
	# got the vehicle instead.
	var fov_now: float = deg_to_rad(_cam.fov if is_instance_valid(_cam) else ZOOMS[zoom_step])
	var best_ang: float = minf(deg_to_rad(1.5), fov_now / 12.0)
	var me := platform
	# Whose side the thing is on decides whether it can be taken at all, before
	# how close to the crosshair it is. There was no team test here: the sight
	# took whatever sat nearest the middle, so a friendly between you and what
	# you were aiming at simply won, and the track jumped to your own side.
	var my_team: int = int(me.team) if ("team" in me) else -1
	var friend_ang: float = best_ang
	var friend: Node3D = null
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == me:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if n.is_in_group("no_lock"):
			continue
		var to: Vector3 = n.global_position - origin
		if to.length() > 26000.0:
			continue
		var a := dir.angle_to(to)
		var ours: bool = ("team" in n) and int(n.team) == my_team
		if ours:
			# remembered, but only used if there is nothing hostile in the cone
			if a < friend_ang:
				friend_ang = a
				friend = n as Node3D
			continue
		if a < best_ang:
			best_ang = a
			best = n
	# One of your own under the crosshair is not taken. Laying fire close to
	# friends means holding the ground beside them, and a sight that jumps
	# onto the friend instead is a sight aimed at him.
	if best == null and friend != null:
		Sim.report("friendly under the sight — holding the ground, not the unit", Sim.Ev.INFO)
	if best:
		tracked = best
		_track_last = best.global_position
		mode = POINT
		_hand_over(best)
		Sim.report("pod tracking %s" % Sim.label_of(best), Sim.Ev.GOOD)
	else:
		var hit := _ground_hit(origin, dir)
		if hit != Vector3.INF:
			area_point = hit
			mode = AREA
			tracked = null
			# hand the spot to the weapons as a real target so a bomb can use it
			if _marker == null or not is_instance_valid(_marker):
				_marker = LaserSpot.new()
				_marker.name = "Designated point"
				get_tree().current_scene.add_child(_marker)
			_marker.global_position = hit
			_hand_over(_marker)
			Sim.report("pod area track designated  %.0f m"
				% origin.distance_to(hit), Sim.Ev.INFO)

## Laser designator: paints the aim point and hands it to the weapons as a
## target, so a bomb or a missile will guide onto whatever the pod is holding.
func toggle_laser() -> void:
	lasing = not lasing
	if lasing:
		_select_spot = true
		Sim.report("laser on — designating", Sim.Ev.GOOD)
	else:
		Sim.report("laser off", Sim.Ev.INFO)
		if _beam:
			_beam.visible = false

## Keep the spot's own idea of itself current: whose it is, whether the laser
## is on it, and what it is riding when the track is on a moving thing.
func _refresh_spot() -> void:
	if _marker == null or not is_instance_valid(_marker):
		return
	var lit: bool = lasing and active and _beam != null and _beam.visible
	_marker.lasing = lit
	_marker.on = lit or (active and mode == AREA)
	_marker.follow = tracked if (mode == POINT and is_instance_valid(tracked)) else null
	if is_instance_valid(platform) and "team" in platform:
		_marker.team = int(platform.get("team"))

## Put the laser away: nothing of it should be visible with the page closed.
func _stow() -> void:
	if _marker != null and is_instance_valid(_marker):
		# An area track is still held with the page shut -- the main view marks
		# it -- so it stays a mark the aeroplane can be locked on.
		_marker.on = mode == AREA
		_marker.lasing = false
	if _beam != null and is_instance_valid(_beam):
		_beam.visible = false
	if _marker != null and is_instance_valid(_marker):
		_marker.visible = false
	if plane() != null:
		plane().designated = Vector3.INF
		plane().designated_node = null
		# A point track is a radar lock and outlives the page: closing the pod
		# hands the contact to the aeroplane rather than dropping it. Only the
		# laser spot, which is a place rather than a thing, is let go.
		if mode == POINT and is_instance_valid(tracked):
			plane().target = tracked
		elif mode != AREA and _marker != null and plane() != null \
				and plane().target == _marker:
			plane().target = null

func _update_laser() -> void:
	if _beam == null:
		var st := MeshKit.begin()
		MeshKit.cone(st, 0.12, 0.12, 0.0, -1.0, Vector3.ZERO, 5, false)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.25, 0.18, 0.5)
		_beam = MeshKit.mi(MeshKit.finish(st, m), "LaserBeam")
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(_beam)
	var p := aim_point()
	_beam.visible = lasing and active and p != Vector3.INF
	if not _beam.visible:
		return
	var origin := _head_origin()
	var reach := origin.distance_to(p)
	if reach < 1.0:
		# the spot has collapsed onto the head — usually because whatever was
		# being tracked has just been destroyed. Pointing a zero length beam
		# raises, and the raise takes the rest of this function with it.
		_beam.visible = false
		return
	_beam.global_position = origin
	_beam.look_at(p, Vector3.UP)
	_beam.scale = Vector3(1, 1, reach)
	if _marker == null or not is_instance_valid(_marker):
		_marker = LaserSpot.new()
		_marker.name = "Laser spot"
		get_tree().current_scene.add_child(_marker)
	_marker.visible = true
	_marker.global_position = p
	# Selected when the laser comes on, and from then on it is one contact among
	# the others: T walks off it and back onto it like anything else.
	if _select_spot and plane() != null:
		plane().target = _marker
		_select_spot = false

func break_lock() -> void:
	if mode != SLEW:
		_sync_head()
	mode = SLEW
	tracked = null

## March the analytic height field to find where the pod is looking.
func _ground_hit(origin: Vector3, dir: Vector3) -> Vector3:
	# Only a ray aimed frankly at the sky is refused. Requiring it to point
	# *down* is an aeroplane's assumption: from a boat the sight sits a few
	# metres above the water and the coast you are looking at is above you, so
	# every mark on land was thrown out before the march even started and a
	# submarine could not take a patch of ground at all.
	if dir.y > 0.30:
		return Vector3.INF
	var t := 20.0
	var prev := origin
	while t < 30000.0:
		var p := origin + dir * t
		# The sea is a surface. Marching only against the height field put the
		# spot on the seabed a couple of hundred metres down, so a bomb aimed at
		# a ship dived past it looking for a mark that was underneath.
		var sea_s: float = Sim.sea_at(p.x, p.z)
		if p.y <= sea_s and Sim.height_at(p.x, p.z) < sea_s:
			var f: float = (prev.y - sea_s) / maxf(prev.y - p.y, 0.001)
			return prev.lerp(p, clampf(f, 0.0, 1.0))
		if p.y <= Sim.height_at(p.x, p.z):
			for i in 12:                       # bisect onto the surface
				var mid := (prev + p) * 0.5
				if mid.y <= Sim.height_at(mid.x, mid.z):
					p = mid
				else:
					prev = mid
			return p
		prev = p
		t += maxf(t * 0.06, 25.0)
	return Vector3.INF

## Where the sensor head sits. A fixed 1.1 m below the origin is under the nose
## of a fighter and buried inside the fuselage of a gunship, which is why the
## AC-130's picture was full of its own aeroplane. Read the hull line out of the
## section table and hang the head below it, on the port side for a gunship,
## which is where that aeroplane actually carries its sensors.
## The pose to hang the sensor off. The *interpolated* one: the head is placed
## in `_process`, once per rendered frame, while the aircraft it is bolted to
## moves once per physics tick. Reading the stepped transform puts the camera a
## fraction of a tick away from the aeroplane on every frame, which is a shake
## you can see against your own wing — the same fault the weapon camera had.
func _mount_xf(n: Node3D) -> Transform3D:
	if n.is_inside_tree():
		return n.get_global_transform_interpolated()
	return n.global_transform

func _head_origin() -> Vector3:
	# On a ship the head is at the masthead, not wherever the parked aeroplane
	# happens to be sitting on the ramp.
	if is_instance_valid(platform) and not (platform is Aircraft):
		# Whatever the mount says its sight sits at. A tank's is two and a half
		# metres; assuming a ship's masthead put an armoured vehicle's sensor
		# eighteen metres above its own turret.
		var lift := 18.0
		if platform.has_method("sight_height"):
			lift = float(platform.call("sight_height"))
		elif platform.has_method("mast_height"):
			lift = float(platform.call("mast_height"))
		return _mount_xf(platform).origin + Vector3(0, lift, 0)
	var z := -1.8
	var bottom := -1.1
	var half_w := 0.8
	var secs: Array = plane().spec["shape"]["sections"]
	for i in secs.size() - 1:
		var z0: float = secs[i][0]
		var z1: float = secs[i + 1][0]
		if z >= minf(z0, z1) and z <= maxf(z0, z1):
			var f: float = (z - z0) / maxf(z1 - z0, 0.001)
			half_w = lerpf(float(secs[i][1]), float(secs[i + 1][1]), f)
			var hh: float = lerpf(float(secs[i][2]), float(secs[i + 1][2]), f)
			var cy: float = lerpf(float(secs[i][3]), float(secs[i + 1][3]), f)
			bottom = cy - hh
			break
	var lat := 0.0
	if bool(plane().spec.get("gunship", false)):
		lat = -half_w * 0.72          # port blister, clear of the belly
	return _mount_xf(plane()) * Vector3(lat, bottom - 0.5, z)

func _aim_dir() -> Vector3:
	if mode == POINT and is_instance_valid(tracked):
		# the target is stepped too, so take its interpolated pose as well
		return (_mount_xf(tracked).origin - _head_origin()).normalized()
	if mode == AREA:
		return (area_point - _head_origin()).normalized()
	# Off whatever is carrying it. Reading the aeroplane first and only then
	# checking for a ship dereferenced a null every frame on a crewed hull.
	var c := platform
	if c == null:
		return Vector3.FORWARD
	var b := _mount_xf(c).basis
	return (b * (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, -1))).normalized()

## Where the point track's target was last seen, so the sensor can hold the
## place when the thing is gone.
var _track_last := Vector3.INF

## The thing being tracked has been destroyed, or has gone: hold the ground it
## was on. Dropping back to slew put the head wherever its gimbal happened to
## rest and left you hunting for the spot you had just hit -- with a column
## half killed and the rest of it still there.
func _hold_area(p: Vector3) -> void:
	tracked = null
	if p == Vector3.INF:
		break_lock()
		return
	var g := Vector3(p.x, maxf(Sim.height_at(p.x, p.z), Sim.sea_at(p.x, p.z)), p.z)
	area_point = g
	mode = AREA
	if _marker == null or not is_instance_valid(_marker):
		_marker = LaserSpot.new()
		_marker.name = "Designated point"
		get_tree().current_scene.add_child(_marker)
	_marker.global_position = g
	_marker.on = true
	# The aeroplane's lock comes with it onto the place, if it was on the thing
	# that has gone; a lock on something else is left alone.
	var pl := plane()
	if pl != null:
		if pl.target == null or not is_instance_valid(pl.target):
			pl.target = _marker
	elif platform != null:
		_hand_over(_marker)
	Sim.report("target down — sensor holding the area", Sim.Ev.INFO)

func _process(delta: float) -> void:
	# Watched whether the page is up or not: a target killed with the page
	# closed is a target killed all the same.
	if mode == POINT:
		if is_instance_valid(tracked) and not (tracked.has_method("is_alive")
				and not tracked.is_alive()):
			_track_last = tracked.global_position
		else:
			_hold_area(_track_last)
	if not active or platform == null:
		# The beam lives in the world, not on the page. Without this it kept
		# whatever state it had when the pod was closed -- visible from the
		# cockpit and the chase camera, still pointing at a spot the aeroplane
		# had long since flown past.
		_stow()
		return
	_t += delta
	var origin := _head_origin()
	var dir := _aim_dir()
	_cam.fov = lerpf(_cam.fov, ZOOMS[zoom_step], clampf(delta * 8.0, 0.0, 1.0))
	_cam.global_position = origin
	var holder: Node3D = platform
	var up := Vector3.UP if absf(dir.y) < 0.985 or holder == null \
		else _mount_xf(holder).basis.y
	_cam.look_at(origin + dir * 1000.0, up)
	if diag:
		# Against the aeroplane as it is *drawn*, always — not against whatever
		# transform the head happens to use. Measuring the head against its own
		# source is self-referential and reads zero however wrong it is.
		var mount := platform
		var seen: Vector3 = _mount_xf(mount).origin if mount != null else origin
		var rel: Vector3 = origin - seen
		if _diag_prev != Vector3.INF:
			var d := (rel - _diag_prev).length()
			shake_worst = maxf(shake_worst, d)
			shake_sum += d
			shake_n += 1
		_diag_prev = rel
	_update_laser()
	_refresh_spot()
	# hand the aim point to the aeroplane so a guided bomb can follow it
	# Hand the spot to whoever is holding the sensor. On a ship there is no
	# `designated` to write to — the mark goes to the hull as the thing its
	# tubes and battery are laid on, which is what a ship does with a laser.
	var lit: bool = active and lasing
	var who: Node3D = platform
	if plane() != null and who == platform:
		plane().designated = aim_point() if lit else Vector3.INF
		plane().designated_node = tracked if (lit and mode == POINT
			and is_instance_valid(tracked)) else null
	elif who != null and plane() == null and lit:
		if mode == POINT and is_instance_valid(tracked):
			_hand_over(tracked)
		elif _marker != null and is_instance_valid(_marker):
			_hand_over(_marker)
	if _tex != null and _tex.material != null:
		(_tex.material as ShaderMaterial).set_shader_parameter("grain_t", _t * 37.0)
	queue_redraw()

func aim_point() -> Vector3:
	if mode == POINT and is_instance_valid(tracked):
		return tracked.global_position
	if mode == AREA:
		return area_point
	var hit := _ground_hit(_head_origin(), _aim_dir())
	return hit if hit != Vector3.INF else Vector3.INF

func _draw() -> void:
	# Whatever is carrying the sensor. This asked for an aeroplane, and on a
	# boat there is not one — so the whole page returned here and drew nothing
	# at all: no crosshair, no track box, no laser, no controls. Every fix
	# further down this function was unreachable from a bridge.
	if not active or platform == null:
		return
	var g := Color(0.55, 1.0, 0.62)
	var frame: Vector2 = size if fullscreen else SIZE
	draw_rect(Rect2(Vector2.ZERO, frame), g, false, 1.6)
	var c := frame * 0.5
	# crosshair
	draw_line(c - Vector2(26, 0), c - Vector2(7, 0), g, 1.4)
	draw_line(c + Vector2(7, 0), c + Vector2(26, 0), g, 1.4)
	draw_line(c - Vector2(0, 26), c - Vector2(0, 7), g, 1.4)
	draw_line(c + Vector2(0, 7), c + Vector2(0, 26), g, 1.4)
	if mode != SLEW:
		var box := 26.0 if mode == POINT else 34.0
		draw_rect(Rect2(c - Vector2(box, box), Vector2(box, box) * 2.0), g, false, 1.6)
	var names := ["SLEW", "AREA TRACK", "POINT TRACK"]
	draw_string(_font, Vector2(10, 22), names[mode], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, g)
	draw_string(_font, Vector2(frame.x - 150, 22), CHANNEL_NAMES[channel],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, g)
	if lasing:
		draw_string(_font, Vector2(10, 62), "LASER ON", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1.0, 0.35, 0.28))
	# Whatever is carrying the sensor, not only an aeroplane. On a hull this
	# read nothing at all — no weapon, no count, no selector — because it went
	# straight to `aircraft`, and on a boat there is no aircraft.
	var holder: Node3D = platform
	if fullscreen and is_instance_valid(holder):
		var w := ""
		var count := ""
		if plane() != null:
			w = plane().weapon_label(plane().current_weapon())
			var n: int = plane().weapon_count(plane().current_weapon())
			count = "belt" if n < 0 else str(n)
		elif holder.has_method("weapon_label") and _armed(holder):
			w = String(holder.call("weapon_label"))
			if holder.has_method("weapon_state"):
				count = String(holder.call("weapon_state"))
		if w != "":
			draw_string(_font, Vector2(frame.x * 0.5 - 90, frame.y - 54),
				"%s   %s" % [w, count], HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color(1.0, 0.85, 0.4))
		if plane() != null:
			draw_string(_font, Vector2(frame.x * 0.5 - 200, frame.y - 30),
				"1-4 weapon   SPACE fire   CTRL+T track/free   L laser   N channel   wheel zoom   ALT+RMB close",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 0.7))
		elif not _armed(holder):
			# Nothing aboard to shoot with -- the carrier, a merchant hull --
			# so the page is a sensor and says only what a sensor does.
			draw_string(_font, Vector2(frame.x * 0.5 - 150, frame.y - 30),
				"CTRL+T track/free   L laser   N channel   wheel zoom   O close",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 0.7))
		elif holder.has_method("weapons"):
			# The hull's own selector, spelled out with what is chosen marked.
			# A boat has no cockpit to read the selection off, and this page was
			# the only thing on screen while it was up.
			var list: PackedStringArray = holder.call("weapons")
			var sel := int(holder.get("sel_weapon"))
			var row := PackedStringArray()
			for wi in list.size():
				row.append("%d %s%s" % [wi + 1, String(list[wi]).to_upper(),
					" <" if wi == sel else ""])
			draw_string(_font, Vector2(frame.x * 0.5 - 200, frame.y - 30),
				"%s    SPACE fire   CTRL+T track/free   L laser   O close" % "   ".join(row),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 0.7))
	draw_string(_font, Vector2(10, frame.y - 26), "FOV %.1f" % _cam.fov,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, g)
	var p := aim_point()
	var eye: Node3D = platform
	if p != Vector3.INF and is_instance_valid(eye):
		# From whatever is holding the sensor. This went straight to `aircraft`, and
		# in a tank or on a bridge there is no jet — so opening the sight from a
		# vehicle threw on the slant range readout every frame.
		var d := eye.global_position.distance_to(p) * 0.001
		draw_string(_font, Vector2(frame.x - 128, frame.y - 26), "SLANT %.1f km" % d,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, g)
	if mode == POINT and is_instance_valid(tracked):
		draw_string(_font, Vector2(10, 42), str(tracked.name).left(22),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.3))
	_draw_contacts(frame)
	_draw_pointing(frame, g)
	_draw_bomb_mark(frame)
	if fmod(_t, 1.0) < 0.5:
		draw_string(_font, Vector2(frame.x - 66, 22), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1.0, 0.35, 0.3))

## Whether whatever is carrying the sensor has anything to shoot with. Asked of
## the host rather than assumed: the page used to print a selector and a FIRE
## line for anything that answered `weapons`, and a hull that answered with an
## empty list still got "SPACE fire".
func _armed(holder: Node) -> bool:
	if holder == null or not is_instance_valid(holder):
		return false
	if holder.has_method("armed"):
		return bool(holder.call("armed"))
	if holder.has_method("weapons"):
		return not (holder.call("weapons") as PackedStringArray).is_empty()
	return holder.has_method("weapon_label")

## Everything the radar is holding, boxed on the sensor picture. The pod has its
## own camera, so contacts are projected through that rather than the cockpit
## one -- the two are looking in quite different directions.
func _draw_contacts(frame: Vector2) -> void:
	# Whoever is holding the sensor, not just an aeroplane. Guarding on `jet`
	# meant a crewed hull -- ship or tank -- drew no contacts at all.
	var me: Node3D = platform
	if _cam == null or me == null:
		return
	var my_team: int = int(me.team) if ("team" in me) else -1
	var reach: float = maxf(Sim.coverage(my_team), 26000.0)
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == me or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var wp: Vector3 = (n as Node3D).global_position
		var d: float = me.global_position.distance_to(wp)
		if d > reach or _cam.is_position_behind(wp):
			continue
		var sp: Vector2 = _cam.unproject_position(wp)
		if sp.x < 4.0 or sp.y < 4.0 or sp.x > frame.x - 4.0 or sp.y > frame.y - 4.0:
			continue
		var hostile: bool = ("team" in n) and int(n.team) != my_team
		var col := Color(1.0, 0.45, 0.35) if hostile else Color(0.55, 0.85, 1.0)
		var r: float = clampf(2600.0 / maxf(d, 1.0), 7.0, 46.0)
		if n == tracked:
			col = Color(1.0, 0.85, 0.35)
			draw_arc(sp, r + 7.0, 0.0, TAU, 20, col, 2.0)
		draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), col, false, 1.6)
		var nm := str(n.name)
		if n.has_method("display_name"):
			nm = String(n.call("display_name"))
		draw_string(_font, sp + Vector2(r + 4, 4), "%s %.1fkm" % [nm.left(14), d * 0.001],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

## The designated mark and, for a bomb, where an unguided release would fall.
func _draw_bomb_mark(frame: Vector2) -> void:
	# The cross on the aim point belongs to whatever is holding the sensor. This
	# bailed out on a null `jet`, and on a boat there is no jet — so pressing O
	# from a submarine gave you a picture with no aiming mark and no indication
	# of what the sight was on at all.
	if _cam == null or platform == null:
		return
	var p := aim_point()
	if p != Vector3.INF and not _cam.is_position_behind(p):
		var sp: Vector2 = _cam.unproject_position(p)
		if sp.x > 2.0 and sp.y > 2.0 and sp.x < frame.x - 2.0 and sp.y < frame.y - 2.0:
			var col := Color(1.0, 0.35, 0.28) if lasing else Color(1.0, 0.82, 0.35)
			var r := 15.0
			draw_line(sp + Vector2(0, -r), sp + Vector2(r, 0), col, 2.0)
			draw_line(sp + Vector2(r, 0), sp + Vector2(0, r), col, 2.0)
			draw_line(sp + Vector2(0, r), sp + Vector2(-r, 0), col, 2.0)
			draw_line(sp + Vector2(-r, 0), sp + Vector2(0, -r), col, 2.0)
			draw_string(_font, sp + Vector2(r + 5, 4),
				"LASER" if lasing else "MARK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# The ballistic fall of an unguided release, so the run-in can be judged.
	# Only an aeroplane drops anything unguided; a hull's tubes are done here.
	if plane() == null:
		return
	var w: String = plane().current_weapon()
	if w == "gun" or String(WeaponSpec.get_spec(w)["kind"]) != "bomb":
		return
	var q: Vector3 = plane().global_position
	var v: Vector3 = plane().linear_velocity
	for i in 320:
		v.y -= 9.81 * 0.12
		q += v * 0.12
		var bed := Sim.height_at(q.x, q.z)
		if q.y <= maxf(bed, Sim.sea_at(q.x, q.z)):
			break
	if _cam.is_position_behind(q):
		return
	var fp: Vector2 = _cam.unproject_position(q)
	if fp.x < 2.0 or fp.y < 2.0 or fp.x > frame.x - 2.0 or fp.y > frame.y - 2.0:
		return
	draw_arc(fp, 10.0, 0.0, TAU, 18, Color(0.55, 1.0, 0.72), 1.8)
	if p != Vector3.INF:
		draw_string(_font, fp + Vector2(13, -12), "CCIP %.0f m" % Vector2(
			q.x - p.x, q.z - p.z).length(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.55, 1.0, 0.72))

## Where the head is pointing relative to whatever is carrying it.
##
## This was a compass rose with an N at the top, which is the one thing it was
## not: the top of the dial was the nose, and nothing on it said what the nose
## belonged to. What you want to know with your head in the sight is which way
## you are looking off your own vehicle -- out over the port wing, back past
## the turret -- so it draws the vehicle, from above, nose up, and the line of
## sight coming off it. Elevation is the bar beside it.
func _draw_pointing(frame: Vector2, g: Color) -> void:
	var c := Vector2(frame.x - 92.0, frame.y - 104.0)
	var k := 1.0
	var dim := Color(g.r, g.g, g.b, 0.85)
	var shape := PackedVector2Array()
	if platform is Aircraft and bool((platform as Aircraft).spec.get("rotary", false)):
		# a helicopter: pod, boom and the disc over it
		shape = PackedVector2Array([Vector2(0, -22), Vector2(6, -14), Vector2(6, 4), Vector2(2, 10),
			Vector2(2, 30), Vector2(9, 30), Vector2(9, 34), Vector2(-9, 34), Vector2(-9, 30),
			Vector2(-2, 30), Vector2(-2, 10), Vector2(-6, 4), Vector2(-6, -14)])
		draw_arc(c + Vector2(0, -4), 26.0, 0.0, TAU, 28, Color(g.r, g.g, g.b, 0.35), 1.0)
	elif platform is Aircraft:
		shape = PackedVector2Array([Vector2(0, -34), Vector2(4, -18), Vector2(5, -4), Vector2(30, 10),
			Vector2(30, 15), Vector2(5, 12), Vector2(4, 24), Vector2(13, 31), Vector2(13, 34),
			Vector2(0, 31), Vector2(-13, 34), Vector2(-13, 31), Vector2(-4, 24), Vector2(-5, 12),
			Vector2(-30, 15), Vector2(-30, 10), Vector2(-5, -4), Vector2(-4, -18)])
	elif platform is Tank:
		shape = PackedVector2Array([Vector2(-13, -24), Vector2(13, -24), Vector2(13, 24),
			Vector2(-13, 24)])
		for sx in [-1.0, 1.0]:
			draw_rect(Rect2(c.x + sx * 13.0 - 2.5, c.y - 26.0, 5.0, 52.0), dim, false, 1.0)
		draw_arc(c, 8.0, 0.0, TAU, 16, dim, 1.2)
	else:
		# a hull: sharp at the bow, square at the stern
		shape = PackedVector2Array([Vector2(0, -36), Vector2(8, -18), Vector2(9, 28), Vector2(6, 34),
			Vector2(-6, 34), Vector2(-9, 28), Vector2(-8, -18)])
		draw_rect(Rect2(c.x - 4.0, c.y - 6.0, 8.0, 16.0), dim, false, 1.0)
	var pts := PackedVector2Array()
	for q in shape:
		pts.append(c + q * k)
	pts.append(pts[0])
	draw_polyline(pts, dim, 1.4)
	# The line of sight: a wedge as wide as the picture is, so zooming in
	# narrows it, and shorter the more steeply the head is looking down.
	var fov: float = deg_to_rad(_cam.fov if is_instance_valid(_cam) else 20.0)
	var half: float = clampf(fov * 0.5, 0.03, 0.6)
	var reach: float = 46.0 * clampf(cos(pitch), 0.3, 1.0) + 8.0
	var hot := Color(1.0, 0.85, 0.35)
	var l := c + Vector2(-sin(yaw + half), -cos(yaw + half)) * reach
	var r := c + Vector2(-sin(yaw - half), -cos(yaw - half)) * reach
	draw_colored_polygon(PackedVector2Array([c, l, r]), Color(1.0, 0.85, 0.35, 0.22))
	draw_line(c, l, hot, 1.4)
	draw_line(c, r, hot, 1.4)
	draw_line(c, c + Vector2(-sin(yaw), -cos(yaw)) * (reach + 6.0), hot, 2.0)
	# elevation: level at the top of the bar, straight down at the bottom
	var bx: float = c.x + 58.0
	draw_line(Vector2(bx, c.y - 34.0), Vector2(bx, c.y + 34.0), dim, 1.2)
	draw_line(Vector2(bx - 4.0, c.y - 34.0), Vector2(bx + 4.0, c.y - 34.0), dim, 1.2)
	var ey: float = c.y - 34.0 + clampf(-pitch / 1.5, -0.2, 1.0) * 68.0
	draw_colored_polygon(PackedVector2Array([Vector2(bx - 8.0, ey), Vector2(bx - 1.0, ey - 4.0),
		Vector2(bx - 1.0, ey + 4.0)]), hot)
	var side := "AHEAD"
	var deg: float = rad_to_deg(wrapf(-yaw, -PI, PI))
	if absf(deg) > 150.0:
		side = "ASTERN"
	elif deg > 30.0:
		side = "STARBOARD" if not (platform is Tank) else "RIGHT"
	elif deg < -30.0:
		side = "PORT" if not (platform is Tank) else "LEFT"
	draw_string(_font, c + Vector2(-50, 56),
		"%s %03d   DOWN %02d" % [side, int(absf(deg)), int(maxf(rad_to_deg(-pitch), 0.0))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, g)


## The pod's mark, as a contact the rest of the aeroplane can see.
##
## It was a bare node, so it was nothing to anything that looks for contacts:
## not on the radar, not in the T cycle, and the only way a weapon learned of it
## was by being handed it. A laser-guided rocket is fired *at* the spot, so the
## spot has to be something you can pick. Not in "hittable" -- rounds would
## burst on it and the opposition would shoot at it -- but in a group of its
## own that the radar and the target cycle read.
class LaserSpot extends Node3D:
	var team := 0
	## Whether it is a mark at all just now: the laser is on it, or the pod is
	## holding it as an area track.
	var on := false
	var lasing := false
	## What it is riding, when the track is on a thing rather than a place.
	var follow: Node3D = null

	func _ready() -> void:
		add_to_group("laser_spots")

	func display_name() -> String:
		return "LASER SPOT" if lasing else "DESIGNATED POINT"

	func is_alive() -> bool:
		return true

	func hit_radius() -> float:
		return 2.0

	func get_velocity() -> Vector3:
		if is_instance_valid(follow):
			if "linear_velocity" in follow:
				return follow.get("linear_velocity")
			if follow.has_method("get_velocity"):
				return follow.call("get_velocity")
		return Vector3.ZERO
