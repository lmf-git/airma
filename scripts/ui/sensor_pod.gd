class_name SensorPod
extends Control
## Targeting pod page. ALT + right click opens it, the mouse slews the head, and
## CTRL+T either point-tracks whatever is under the crosshair or ground
## stabilises on the spot it is looking at.

enum { SLEW, AREA, POINT }

const SIZE := Vector2(360, 360)

var jet: Aircraft = null
var host: Node3D = null          # a ship or vehicle the pod is mounted on instead
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
var _marker: Node3D
var lasing := false
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
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
const CHANNEL_NAMES := ["TV", "NIGHT", "WHOT", "BHOT"]
var channel := CH_WHOT

func _flir_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.16;
uniform int channel = 2;      // 0 TV, 1 night, 2 white hot, 3 black hot
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

## Step through the sensor channels.
func cycle_channel() -> void:
	channel = (channel + 1) % 4
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
	_vp.size = Vector2i(want)
	_tex.size = want
	queue_redraw()

func toggle() -> void:
	active = not active
	visible = active
	# Coming back to the page keeps whatever the pod was holding. Resetting to
	# SLEW on every activation threw away a point track the moment you looked
	# away from the sensor page, which is the one thing a track is for.
	if active and carrier() != null and mode == SLEW and not is_instance_valid(tracked):
		yaw = 0.0
		pitch = -0.35
	if not active:
		_stow()

func slew(rel: Vector2) -> void:
	if not active:
		return
	yaw = clampf(yaw - rel.x * 0.0022, -2.4, 2.4)
	pitch = clampf(pitch - rel.y * 0.0022, -1.5, 0.35)
	mode = SLEW
	tracked = null

func zoom(dir: int) -> void:
	zoom_step = clampi(zoom_step + dir, 0, ZOOMS.size() - 1)

## CTRL+T: point track what is under the crosshair, otherwise ground stabilise.
## Whatever the sensor is bolted to. A crewed ship sets `host` and leaves `jet`
## as whatever it was — usually null once the player has left the aeroplane —
## so every one of these guards failed and a ship's sensor could not track
## anything at all, point or area.
func carrier() -> Node3D:
	if host != null and is_instance_valid(host):
		return host
	return jet if is_instance_valid(jet) else null

## Hand a contact or a place to whatever is holding the sensor. An aeroplane
## keeps it as its radar target; a ship keeps it as the thing its tubes and its
## battery are laid on.
func _hand_over(t: Node3D) -> void:
	var c := carrier()
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
	elif is_instance_valid(jet):
		jet.target = t

func designate() -> void:
	if not active or carrier() == null:
		return
	var origin := _head_origin()
	var dir := _aim_dir()
	var best: Node3D = null
	var best_ang := deg_to_rad(2.6)
	var me := carrier()
	# Whose side the thing is on decides whether it can be taken at all, before
	# how close to the crosshair it is. There was no team test here: the sight
	# took whatever sat nearest the middle, so a friendly between you and what
	# you were aiming at simply won, and the track jumped to your own side.
	var my_team: int = int(me.team) if ("team" in me) else -1
	var friend_ang := deg_to_rad(2.6)
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
	if best == null and friend != null:
		best = friend
	if best:
		tracked = best
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
				_marker = Node3D.new()
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
		Sim.report("laser on — designating", Sim.Ev.GOOD)
	else:
		Sim.report("laser off", Sim.Ev.INFO)
		if _beam:
			_beam.visible = false

## Put the laser away: nothing of it should be visible with the page closed.
func _stow() -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.visible = false
	if _marker != null and is_instance_valid(_marker):
		_marker.visible = false
	if jet != null and is_instance_valid(jet):
		jet.designated = Vector3.INF
		jet.designated_node = null
		# A point track is a radar lock and outlives the page: closing the pod
		# hands the contact to the aeroplane rather than dropping it. Only the
		# laser spot, which is a place rather than a thing, is let go.
		if mode == POINT and is_instance_valid(tracked):
			jet.target = tracked
		elif _marker != null and jet.target == _marker:
			jet.target = null

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
		_marker = Node3D.new()
		_marker.name = "Laser spot"
		get_tree().current_scene.add_child(_marker)
	_marker.visible = true
	_marker.global_position = p
	if jet:
		jet.target = _marker

func break_lock() -> void:
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
		if p.y <= Sim.WATER_LEVEL and Sim.height_at(p.x, p.z) < Sim.WATER_LEVEL:
			var f: float = (prev.y - Sim.WATER_LEVEL) / maxf(prev.y - p.y, 0.001)
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
	if host != null and is_instance_valid(host):
		# Whatever the host says its sight sits at. A tank's is two and a half
		# metres; assuming a ship's masthead put an armoured vehicle's sensor
		# eighteen metres above its own turret.
		var lift := 18.0
		if host.has_method("sight_height"):
			lift = float(host.call("sight_height"))
		elif host.has_method("mast_height"):
			lift = float(host.call("mast_height"))
		return _mount_xf(host).origin + Vector3(0, lift, 0)
	var z := -1.8
	var bottom := -1.1
	var half_w := 0.8
	var secs: Array = jet.spec["shape"]["sections"]
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
	if bool(jet.spec.get("gunship", false)):
		lat = -half_w * 0.72          # port blister, clear of the belly
	return _mount_xf(jet) * Vector3(lat, bottom - 0.5, z)

func _aim_dir() -> Vector3:
	if mode == POINT and is_instance_valid(tracked):
		# the target is stepped too, so take its interpolated pose as well
		return (_mount_xf(tracked).origin - _head_origin()).normalized()
	if mode == AREA:
		return (area_point - _head_origin()).normalized()
	# Off whatever is carrying it. Reading the aeroplane first and only then
	# checking for a ship dereferenced a null every frame on a crewed hull.
	var c := carrier()
	if c == null:
		return Vector3.FORWARD
	var b := _mount_xf(c).basis
	return (b * (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, -1))).normalized()

func _process(delta: float) -> void:
	if not active or carrier() == null:
		# The beam lives in the world, not on the page. Without this it kept
		# whatever state it had when the pod was closed -- visible from the
		# cockpit and the chase camera, still pointing at a spot the aeroplane
		# had long since flown past.
		_stow()
		return
	_t += delta
	if mode == POINT and (not is_instance_valid(tracked)
			or (tracked.has_method("is_alive") and not tracked.is_alive())):
		break_lock()
	var origin := _head_origin()
	var dir := _aim_dir()
	_cam.fov = lerpf(_cam.fov, ZOOMS[zoom_step], clampf(delta * 8.0, 0.0, 1.0))
	_cam.global_position = origin
	var holder: Node3D = carrier()
	var up := Vector3.UP if absf(dir.y) < 0.985 or holder == null \
		else _mount_xf(holder).basis.y
	_cam.look_at(origin + dir * 1000.0, up)
	if diag:
		# Against the aeroplane as it is *drawn*, always — not against whatever
		# transform the head happens to use. Measuring the head against its own
		# source is self-referential and reads zero however wrong it is.
		var mount := carrier()
		var seen: Vector3 = _mount_xf(mount).origin if mount != null else origin
		var rel: Vector3 = origin - seen
		if _diag_prev != Vector3.INF:
			var d := (rel - _diag_prev).length()
			shake_worst = maxf(shake_worst, d)
			shake_sum += d
			shake_n += 1
		_diag_prev = rel
	_update_laser()
	# hand the aim point to the aeroplane so a guided bomb can follow it
	# Hand the spot to whoever is holding the sensor. On a ship there is no
	# `designated` to write to — the mark goes to the hull as the thing its
	# tubes and battery are laid on, which is what a ship does with a laser.
	var lit: bool = active and lasing
	var who: Node3D = carrier()
	if jet != null and is_instance_valid(jet) and who == jet:
		jet.designated = aim_point() if lit else Vector3.INF
		jet.designated_node = tracked if (lit and mode == POINT
			and is_instance_valid(tracked)) else null
	elif who != null and who != jet and lit:
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
	if not active or carrier() == null:
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
	# straight to `jet`, and on a boat there is no jet.
	var holder: Node3D = carrier()
	if fullscreen and is_instance_valid(holder):
		var w := ""
		var count := ""
		if holder == jet and jet != null:
			w = jet.weapon_label(jet.current_weapon())
			var n: int = jet.weapon_count(jet.current_weapon())
			count = "belt" if n < 0 else str(n)
		elif holder.has_method("weapon_label"):
			w = String(holder.call("weapon_label"))
			if holder.has_method("weapon_state"):
				count = String(holder.call("weapon_state"))
		if w != "":
			draw_string(_font, Vector2(frame.x * 0.5 - 90, frame.y - 54),
				"%s   %s" % [w, count], HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color(1.0, 0.85, 0.4))
		if holder == jet:
			draw_string(_font, Vector2(frame.x * 0.5 - 200, frame.y - 30),
				"1-4 weapon   SPACE fire   CTRL+T track   L laser   N channel   wheel zoom   ALT+RMB close",
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
				"%s    SPACE fire   CTRL+T track   L laser   O close" % "   ".join(row),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 0.7))
	draw_string(_font, Vector2(10, frame.y - 26), "FOV %.1f" % _cam.fov,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, g)
	var p := aim_point()
	if p != Vector3.INF:
		var d := jet.global_position.distance_to(p) * 0.001
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

## Everything the radar is holding, boxed on the sensor picture. The pod has its
## own camera, so contacts are projected through that rather than the cockpit
## one -- the two are looking in quite different directions.
func _draw_contacts(frame: Vector2) -> void:
	# Whoever is holding the sensor, not just an aeroplane. Guarding on `jet`
	# meant a crewed hull -- ship or tank -- drew no contacts at all.
	var me: Node3D = carrier()
	if _cam == null or me == null:
		return
	var my_team: int = int(me.team) if ("team" in me) else -1
	var reach: float = maxf(Sim.radar_range(), 26000.0)
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
	if _cam == null or carrier() == null:
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
	if not is_instance_valid(jet) or carrier() != jet:
		return
	var w: String = jet.current_weapon()
	if w == "gun" or String(WeaponSpec.get_spec(w)["kind"]) != "bomb":
		return
	var q: Vector3 = jet.global_position
	var v: Vector3 = jet.linear_velocity
	for i in 320:
		v.y -= 9.81 * 0.12
		q += v * 0.12
		var bed := Sim.height_at(q.x, q.z)
		if q.y <= maxf(bed, Sim.WATER_LEVEL if bed < Sim.WATER_LEVEL else bed):
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

## Where the head is pointing relative to the nose. Without this the picture
## gives you no idea whether you are looking off the left wing or over your
## shoulder.
func _draw_pointing(frame: Vector2, g: Color) -> void:
	var c := Vector2(frame.x - 86.0, frame.y - 96.0)
	var rad := 40.0
	draw_arc(c, rad, 0.0, TAU, 32, g, 1.4)
	# nose marker at the top
	draw_line(c + Vector2(0, -rad - 6), c + Vector2(0, -rad + 6), g, 2.0)
	draw_string(_font, c + Vector2(-8, -rad - 10), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, g)
	for a in [PI * 0.5, PI, PI * 1.5]:
		draw_line(c + Vector2(sin(a), -cos(a)) * (rad - 5.0),
			c + Vector2(sin(a), -cos(a)) * rad, g, 1.0)
	# the head: azimuth round the dial, elevation as the length of the needle
	var lean: float = clampf(1.0 - absf(pitch) / 1.55, 0.25, 1.0)
	var tip := c + Vector2(sin(yaw), -cos(yaw)) * rad * lean
	draw_line(c, tip, Color(1.0, 0.85, 0.35), 2.4)
	draw_circle(tip, 3.4, Color(1.0, 0.85, 0.35))
	draw_string(_font, c + Vector2(-46, rad + 18),
		"AZ %+04d  EL %+03d" % [int(rad_to_deg(yaw)), int(rad_to_deg(pitch))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, g)
