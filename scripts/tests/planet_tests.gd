class_name PlanetTests
extends TestSuite
## The planet seen from far off: sky, clouds, sun, globe, chart and map, and
## what drawing it all costs.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a.begins_with("--fpslog"):
		_fps_log = true
	elif a.begins_with("--fpstest"):
		# Seconds to watch for, so a long look is one flag rather than a
		# rebuild: --fpstest or --fpstest=20.
		_fps_test = float(a.substr(10)) if a.length() > 9 else 12.0
		world.get_tree().node_added.connect(_fps_arrived)
		Sim.profiling = true
		Sim.prof_reset()
		# A benchmark must never be measuring the refresh rate. Pinned to
		# vsync every result reads "the same as every other" until the
		# machine can no longer keep up, so a change that costs a third of
		# the budget is invisible until it costs all of it -- which is
		# exactly what happened here: three separate optimisations all
		# measured 16.4 ms because 16.4 ms was the screen, not the game.
		if not OS.has_feature("headless"):
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	elif a == "--cloudtest":
		_cloud_test = true
	elif a == "--globeworld":
		_globe_world = true
	elif a == "--charttest":
		_chart_test = true
	elif a == "--maptest":
		_map_test = true
	elif a == "--globetest":
		_globe_test = true
	elif a == "--patchtest":
		_patch_test = true
	elif a == "--airtest":
		_air_test = true
	elif a == "--suntest":
		_sun_test = true
	elif a == "--layertest":
		_layer_test = true
	elif a == "--mapshot":
		_map_shot = true
	elif a == "--costtest":
		_cost_test = true
	elif a == "--planettest":
		_planet_test = true
	elif a == "--skytest":
		_sky_test = true
	elif a == "--geomtest":
		_geomtest = true
	elif a == "--culltest":
		_culltest = true
	else:
		return false
	return true


#region --fpslog --fpstest
var _fps_test := 0.0
var _fps_steps: Array = []
var _fps_script: Array = []
var _fps_tick_was := 0
var _fps_script_was := 0.0
## What joined the tree this frame, by the top-level thing it joined under.
var _fps_new := {}
var _fps_new_most := 0
var _fps_new_worst := {}
var _fps_clock := 0.0
## The engine's own two clocks, sampled every frame of the run alongside the
## frame time so the report can quote a median rather than whatever the last
## instant happened to hold.
var _fps_proc: Array = []
var _fps_phys: Array = []
## What the renderer itself measured: the CPU building the frame's command
## lists, and the GPU executing them. "Process 12 ms" includes waiting on the
## GPU, so on its own it cannot say which of the two is the frame.
var _fps_rcpu: Array = []
var _fps_rgpu: Array = []
var _fps_nodes: Array = []
## Each stall, with the tagged blocks that grew most across it. "worst 48 ms"
## with nobody's name on it is a number to stare at; this names the suspects,
## or says it was none of them -- which points at the engine.
var _fps_stalls: Array = []
var _fps_prof_prev: Dictionary = {}
var _fps_times: PackedFloat32Array = PackedFloat32Array()
var _fps_log := false
var _fps_t := 0.0
var _fps_n := 0
var _fps_sum := 0.0

func tick_fps_log(delta: float) -> void:
	if _fps_log:
		_fps_clock += delta
		_fps_sum += Engine.get_frames_per_second()
		_fps_n += 1
		if _fps_t >= 2.0:
			print("[perf] fps=%5.1f  draw calls=%5d  objects=%5d  prims=%8d  mem=%4d MB" % [
				_fps_sum / float(maxi(_fps_n, 1)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])
			_fps_t = 0.0
			_fps_n = 0
			_fps_sum = 0.0

# Where the frame goes.
# Once it has started, it finishes.
#
# This read `and running`, and the mission it measures is a battle: when the
# player is shot down `running` goes false, the clock stops where it is and
# the report is never printed. The run then sits there until it is killed,
# which is what happened twice while measuring the road change -- one run
# reported 30 ms and the next two reported nothing at all.
func tick_fps(delta: float) -> bool:
	if _fps_test > 0.0 and (world.running or _fps_clock > 0.0):
		_fps_clock += delta
		# The first second is thrown away: shaders are still compiling, chunks
		# are still arriving, and the worst frame in a game's life is its first.
		if _fps_clock > 1.0:
			_fps_times.append(delta)
			if delta > 0.020 and _fps_stalls.size() < 12:
				var grew: Array = []
				for tag in Sim._prof:
					var g: float = float(Sim._prof[tag]) - float(_fps_prof_prev.get(tag, 0.0))
					if g > 500.0 and not String(tag).ends_with(".total"):
						grew.append([g, String(tag)])
				grew.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
				var who := PackedStringArray()
				for gw in grew.slice(0, 4):
					who.append("%s %.1f ms" % [String(gw[1]), float(gw[0]) * 0.001])
				_fps_stalls.append("%.1f ms at %.1f s: %s" % [delta * 1000.0, _fps_clock,
					", ".join(who) if not who.is_empty() else "nothing tagged -- the engine's own"])
			_fps_prof_prev = Sim._prof.duplicate()
			# Sampled with the frame time, not read once when the report is
			# printed. Read at the end they are whatever the engine happened to
			# be doing at that instant -- and it showed: a run whose frames
			# measured 11.4 ms reported a 19.5 ms process time and a 5.1 ms
			# physics step, which cannot both be true of the same frame.
			_fps_proc.append(
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_fps_phys.append(Performance.get_monitor(
				Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			var vrid := world.get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vrid, true)
			_fps_rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vrid)
				+ RenderingServer.get_frame_setup_time_cpu())
			_fps_rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vrid))
			# The cheapest witness to what a frame was doing. A stall in a
			# battle is nearly always something *arriving* -- an aeroplane
			# built, a wreck made, an effect spawned -- and without this
			# "worst 96.83 ms" is a number with nobody's name on it.
			_fps_nodes.append(
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			# How many physics ticks this frame carried, and what the tagged
			# scripts cost in it: the two things that can make one frame
			# dearer than its neighbours without anything arriving.
			var tick_now: int = Engine.get_physics_frames()
			_fps_steps.append(tick_now - _fps_tick_was)
			_fps_tick_was = tick_now
			var tagged := 0.0
			for tg in Sim._prof:
				if not String(tg).ends_with(".total"):
					tagged += float(Sim._prof[tg])
			_fps_script.append((tagged - _fps_script_was) * 0.001)
			_fps_script_was = tagged
			# ...and whose they were, for the frame that brought the most.
			var came := 0
			for k in _fps_new:
				came += int(_fps_new[k])
			if came > _fps_new_most:
				_fps_new_most = came
				_fps_new_worst = _fps_new.duplicate()
		_fps_new.clear()
		if _fps_clock > _fps_test + 1.0:
			_fps_test = 0.0
			_run_fps_test()
			world.get_tree().quit()
			return true
	return false

func _fps_arrived(n: Node) -> void:
	var top: Node = n
	while top.get_parent() != null and top.get_parent() != world:
		top = top.get_parent()
	var key := String(top.name) if top.get_parent() == world else "(elsewhere)"
	# numbered siblings are one kind of thing
	key = key.rstrip("0123456789 -@")
	_fps_new[key] = int(_fps_new.get(key, 0)) + 1

## Where the frame goes.
##
## Two questions, and they want different answers. *How fast is it* is the
## distribution of frame times — and the mean is the least useful number in it,
## because a game that holds 90 and hitches to 8 four times a second reads as
## smooth on a mean and is unplayable. So the percentiles are what is printed,
## and the worst frame with them.
##
## *Where did it go* is the breakdown, which is the number you can act on. Each
## line is what that block cost **per frame of the whole run**, not per call, so
## a thing that runs once every eighty frames and costs 12 ms shows up as the
## 0.15 ms a frame it actually is — and a thing that runs every frame and costs
## 0.4 ms shows up as bigger, because it is.
func _run_fps_test() -> void:
	var n := _fps_times.size()
	if n < 8:
		print("[fps] RESULT: FAILED — only %d frames" % n)
		return
	var srt: Array = []
	var total := 0.0
	for v in _fps_times:
		srt.append(float(v))
		total += float(v)
	srt.sort()
	var mean: float = total / float(n)
	var p50: float = float(srt[int(n * 0.50)])
	var p95: float = float(srt[int(n * 0.95)])
	var p99: float = float(srt[mini(int(n * 0.99), n - 1)])
	var worst: float = float(srt[n - 1])
	var vs := "unknown"
	if not OS.has_feature("headless"):
		vs = "OFF" if DisplayServer.window_get_vsync_mode() \
			== DisplayServer.VSYNC_DISABLED else "ON — this is the screen's rate, not the game's"
	print("[fps] %d frames over %.1f s in %s; vsync %s, max_fps %d" % [n, total,
		"the planet" if Sim.globe else "the flat world", vs, Engine.max_fps])
	print("[fps] frame time: median %.2f ms (%.0f fps), 95th %.2f ms (%.0f fps), 99th %.2f ms, worst %.2f ms" % [
		p50 * 1000.0, 1.0 / maxf(p50, 1e-6), p95 * 1000.0,
		1.0 / maxf(p95, 1e-6), p99 * 1000.0, worst * 1000.0])
	print("[fps] mean %.2f ms (%.0f fps) — the least useful number here, and the reason the percentiles are above it" % [
		mean * 1000.0, 1.0 / maxf(mean, 1e-6)])
	# How many frames were bad enough to feel. A hitch is not a slow game; it is
	# a different complaint with a different cause, and it wants counting.
	# Two bars, because they catch different things. Three times the median is a
	# stall you would call a freeze; one and a half is a dropped frame, which is
	# what a periodic 5 ms spike on a 16 ms budget actually produces and what
	# reads as stutter rather than as slowness.
	var hitch := 0
	var dropped := 0
	for v2 in _fps_times:
		if float(v2) > p50 * 3.0:
			hitch += 1
		if float(v2) > p50 * 1.5:
			dropped += 1
	print("[fps] %d frames (%.1f%%) over 1.5x the median, %d (%.1f%%) over 3x — stutter and stalls, which are not slowness" % [
		dropped, 100.0 * float(dropped) / float(n),
		hitch, 100.0 * float(hitch) / float(n)])
	for st in _fps_stalls:
		print("[fps]   stall %s" % String(st))
	# The dropped frames against the rest, by what was in them. "Ten per cent
	# of frames take nearly twice as long" has three quite different causes --
	# a second physics tick, a script that runs on a timer, or the renderer --
	# and they want three different fixes.
	if _fps_steps.size() == n and _fps_script.size() == n and _fps_rgpu.size() == n:
		var slow := [[], [], [], []]
		var rest := [[], [], [], []]
		for i in range(1, n):
			var into: Array = slow if float(_fps_times[i]) > p50 * 1.5 else rest
			(into[0] as Array).append(float(_fps_steps[i]))
			(into[1] as Array).append(float(_fps_script[i]))
			(into[2] as Array).append(float(_fps_rgpu[i]))
			(into[3] as Array).append(float(_fps_rcpu[i]))
		var avg_of := func(a: Array) -> float:
			var t := 0.0
			for v in a:
				t += float(v)
			return t / maxf(float(a.size()), 1.0)
		if not (slow[0] as Array).is_empty():
			print("[fps]   the slow frames: %.2f physics ticks, %.2f ms of tagged script, %.2f ms GPU, %.2f ms render CPU" % [
				avg_of.call(slow[0]), avg_of.call(slow[1]), _median(slow[2]), _median(slow[3])])
			print("[fps]   the others:      %.2f physics ticks, %.2f ms of tagged script, %.2f ms GPU, %.2f ms render CPU" % [
				avg_of.call(rest[0]), avg_of.call(rest[1]), _median(rest[2]), _median(rest[3])])
	# ...and what the worst of them was doing.
	if _fps_nodes.size() == n and n > 2:
		var at := 0
		for i in n:
			if float(_fps_times[i]) > float(_fps_times[at]):
				at = i
		var was := int(_fps_nodes[maxi(at - 1, 0)])
		var now := int(_fps_nodes[mini(at + 1, n - 1)])
		var grew := 0
		var grew_at := 0
		for i in range(1, n):
			var d := int(_fps_nodes[i]) - int(_fps_nodes[i - 1])
			if d > grew:
				grew = d
				grew_at = i
		print("[fps] the worst frame was %.1f ms, %.0f%% of the way through; the tree went %d -> %d nodes across it" % [
			float(_fps_times[at]) * 1000.0, 100.0 * float(at) / float(n),
			was, now])
		print("[fps] the biggest arrival was %+d nodes in one frame, and that frame took %.1f ms" % [
			grew, float(_fps_times[grew_at]) * 1000.0])
		# A count of nodes has nobody's name on it either. These are the
		# things that were put into the tree in the frame that received the
		# most, by the name of whatever they were put in under.
		var who: Array = []
		for k in _fps_new_worst:
			who.append([int(_fps_new_worst[k]), String(k)])
		who.sort_custom(func(a2: Array, b2: Array) -> bool: return int(a2[0]) > int(b2[0]))
		var parts := PackedStringArray()
		for w in who.slice(0, 6):
			parts.append("%s x%d" % [String(w[1]), int(w[0])])
		if not parts.is_empty():
			print("[fps]   the fullest frame took in: %s" % ", ".join(parts))
	# What the renderer was asked to do.
	print("[fps] draw calls %d, primitives %d, video memory %.0f MB, objects %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	# Physics is per *step*, and the step runs at its own rate: at 120 Hz
	# against a frame around 90 that is 1.3 steps a frame, so a millisecond here
	# is nearer one and a third on the frame. The bodies and pairs are printed
	# with it because that is what decides it, and neither is visible anywhere
	# else in this report.
	print("[fps] renderer says: %.2f ms of CPU to build the frame, %.2f ms of GPU to draw it" % [
		_median(_fps_rcpu), _median(_fps_rgpu)])
	print("[fps] engine says: process %.2f ms, physics %.2f ms a step at %d Hz over %d bodies, %d pairs, %d islands" % [
		_median(_fps_proc), _median(_fps_phys),
		Engine.physics_ticks_per_second,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))])
	# And what the renderer was handed, with an address on it.
	var census: Array = _geometry_census()
	var all_tri := 0
	var all_shad := 0
	for c in census:
		all_tri += int((c as Array)[1])
		all_shad += int((c as Array)[2])
	print("[fps] geometry: %.2f M triangles in the tree, %.2f M of it casting shadows" % [
		float(all_tri) / 1e6, float(all_shad) / 1e6])
	for c2 in census:
		var cc: Array = c2
		if int(cc[1]) < 20000:
			continue
		print("[fps]   %-18s %7.2f M tri   %s" % [String(cc[0]),
			float(cc[1]) / 1e6,
			"casts shadow" if int(cc[2]) > 0 else "no shadow"])
	var leaves: Array = _geometry_leaves()
	print("[fps] the meshes it is actually in:")
	for l in leaves.slice(0, 12):
		var ll: Array = l
		print("[fps]   %-18s %7.2f M tri  %6d instances  %s" % [
			String(ll[0]), float(ll[1]) / 1e6, int(ll[2]),
			"shadow" if bool(ll[3]) else "-"])
	# And the breakdown, which is the part you can act on.
	var rows: Array = Sim.prof_report()
	var frames: int = maxi(Sim.prof_frames(), 1)
	var acc := 0.0
	print("[fps] where it went, per frame of the run:")
	for r in rows:
		var rr: Array = r
		var tag := String(rr[0])
		# A tag ending in `.total` wraps other tags, so adding it to the sum
		# counts its children twice. It is printed -- knowing a whole subsystem
		# is a third of a millisecond is worth knowing -- but it is not added.
		var nested: bool = tag.ends_with(".total")
		if not nested:
			acc += float(rr[1])
		print("[fps]   %-18s %7.3f ms   (%d calls in %d frames, %.3f ms a call)%s" % [
			tag, float(rr[1]) * 0.001, int(rr[2]), frames,
			float(rr[1]) * 0.001 / maxf(float(rr[2]) / float(frames), 1e-6),
			"   [contains the below]" if nested else ""])
	print("[fps]   %-18s %7.3f ms of a %.3f ms median frame; the rest is the engine's own -- culling, drawing and physics" % [
		"scripts measured", acc * 0.001, p50 * 1000.0])
	# Nothing is gated on a frame rate: it is a different number on every
	# machine and a test that fails on a slow one is noise. What is gated is
	# that the run happened and the breakdown adds up to less than the frame,
	# which is what says the measurement is honest rather than double counting.
	print("[fps] RESULT: %s" % ("ok" if n > 60 and acc * 0.001 <= p50 * 1000.0 * 1.05
		else "FAILED — the breakdown does not fit inside the frame"))

## The middle of a sample, for the engine clocks gathered beside the frame time.
func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var srt: Array = a.duplicate()
	srt.sort()
	return float(srt[int(srt.size() / 2.0)])

## What the renderer is being asked to draw, and by whom.
##
## Sixteen million primitives a frame is a number with no address on it. This
## walks the tree and puts an address on it: triangles per top-level branch,
## multiplied out for multimeshes, and whether each branch casts a shadow —
## because a shadow-casting mesh is drawn again for every split of the
## directional light, and four splits turns a million triangles into five.
func _geometry_census() -> Array:
	var totals: Dictionary = {}
	var shadowed: Dictionary = {}
	for branch in world.get_children():
		var tag := String(branch.name)
		var tri := 0
		var shad := 0
		var stack: Array = [branch]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			var t := 0
			if n is MultiMeshInstance3D:
				var mm := (n as MultiMeshInstance3D).multimesh
				if mm != null and mm.mesh != null:
					t = _mesh_tris(mm.mesh) * mm.instance_count
			elif n is MeshInstance3D:
				var mi := n as MeshInstance3D
				if mi.mesh != null:
					t = _mesh_tris(mi.mesh)
			if t > 0:
				tri += t
				if (n as GeometryInstance3D).cast_shadow \
						!= GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shad += t
		if tri > 0:
			totals[tag] = tri
			shadowed[tag] = shad
	var out: Array = []
	for k in totals.keys():
		out.append([String(k), int(totals[k]), int(shadowed[k])])
	out.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return out

## The same census, but by the node that actually holds the geometry rather than
## by the branch it hangs under. "Scenery is six million triangles" is not
## something you can act on; "the bushes are three million of it" is.
func _geometry_leaves() -> Array:
	var out: Array = []
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var t := 0
		var inst := 1
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				inst = mm.instance_count
				t = _mesh_tris(mm.mesh) * inst
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				t = _mesh_tris(mi.mesh)
		if t > 20000:
			out.append([String(n.name), t, inst,
				(n as GeometryInstance3D).cast_shadow
					!= GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])
	out.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return out

func _mesh_tris(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		if m is ArrayMesh:
			var idx: int = (m as ArrayMesh).surface_get_array_index_len(i)
			if idx > 0:
				t += int(idx / 3.0)
				continue
			t += int((m as ArrayMesh).surface_get_array_len(i) / 3.0)
		else:
			t += 200
	return t
#endregion


#region --cloudtest
var _cloud_test := false

# Is the cloud layer round the planet, and in front of the ground?
func tick_cloud() -> bool:
	if _cloud_test:
		_cloud_test = false
		_run_cloud_test()
		world.get_tree().quit()
		return true
	return false

## The cloud layer.
##
## What is checked is that there is one of it and that it is round the planet.
## Cloud used to be drawn twice — a slab that followed the camera and a sky
## shader that could only ever be background — and the gap between the two is
## why the sky looked clear with weather piled at the edge. Drawing it twice
## again would be the obvious way to regress this, so the test counts the
## systems as well as measuring the one that is left.
func _run_cloud_test() -> void:
	if not is_instance_valid(world.clouds):
		print("[cloud] RESULT: FAILED — no cloud layer")
		return
	var mi := world.clouds.get_node_or_null("CloudShell") as MeshInstance3D
	if mi == null or mi.mesh == null:
		print("[cloud] RESULT: FAILED — the layer has no mesh")
		return
	# The cloud is round the planet; the mesh it is drawn on is round the camera.
	# A sphere of the layer's own radius has faces three hundred kilometres
	# across that sag under the layer's base, and the cloud was cut off along
	# them. So: is the proxy about the eye, and wholly inside the frustum's
	# depth, so that every pixel is covered from any altitude?
	var vcam: Camera3D = world.get_viewport().get_camera_3d()
	var proxy_r: float = mi.global_transform.basis.get_scale().x
	var proxy_off: float = 1e12
	if vcam != null:
		proxy_off = mi.global_position.distance_to(vcam.global_position)
	var proxy_ok: bool = vcam != null and proxy_off < proxy_r * 0.25 \
		and proxy_r > vcam.near * 4.0 and proxy_r < vcam.far * 0.8
	var faces: PackedVector3Array = mi.mesh.get_faces()
	print("[cloud] drawn on a sphere of %.0f m carried %.1f m from the eye; %d triangles" % [
		proxy_r, proxy_off, int(faces.size() / 3.0)])
	# One system, not two. Both of the old ones are off and have to stay off.
	var sky_off: bool = not Weather.FOG_VOLUME
	print("[cloud] the camera-following slab is %s; the sky's own march is %s" % [
		"off" if sky_off else "ON", "off"])
	# It has to cover the sky from the ground: standing at the airfield, the eye
	# is inside the shell, so it is drawn overhead rather than as a distant lid.
	var eye_r: float = Vector3(0.0, Sim.height_at(0.0, 0.0) + 2.0, 0.0) \
		.distance_to(Sim.planet_centre)
	var inside: bool = eye_r < Sim.PLANET_R + CloudShell.TOP \
		and eye_r < Sim.PLANET_R + CloudShell.BASE
	print("[cloud] from the airfield the eye is %s the layer, %.0f m under its base" % [
		"under" if inside else "NOT under",
		Sim.PLANET_R + CloudShell.BASE - eye_r])
	# How fast the layer actually moves. Written straight into the shader in
	# texture units this was 1275 m/s -- Mach 3.7 of cloud -- because the units
	# are the noise scale over the planet's radius and nobody can eyeball that.
	var drift: float = CloudShell.WIND
	print("[cloud] the layer drifts at %.1f m/s (%.0f km/h)" % [drift, drift * 3.6])
	# and the weather still drives it
	var cover: float = world.weather.cloud_cover()
	print("[cloud] the weather asks for %.2f cover at %.2f density" % [
		cover, world.weather.cloud_density()])
	# How big one cloud is, which is what decides whether you can fly through
	# the layer or merely into it.
	#
	# The field's finest octave is 8.07 times its scale, and the scale is in
	# units to the radian, so the smallest feature is the planet's radius over
	# that. Sampled at `NOISE_SCALE` alone it came to eighty-eight kilometres:
	# an aeroplane entering the layer was inside one cloud for the rest of the
	# flight, and a ray marched along the layer never left it. Everything that
	# looked through cloud -- the windscreen, a seeker, an ASAT -- saw white.
	var coarse_m: float = Sim.PLANET_R / (CloudShell.NOISE_SCALE * CloudShell.SHAPE_COARSE)
	var finest: float = CloudShell.FINEST_M
	# ...and how finely the march samples the near field, because a cloud the
	# ray steps straight over is a cloud that is not there. Geometric steps, so
	# this is the first one.
	var span := 52000.0
	var g := 1.14
	var first_step: float = span * (g - 1.0) \
		/ (pow(g, float(CloudShell.STEPS)) - 1.0)
	print("[cloud] a weather system is %.0f km across and a cloud in it %.1f km; the march's first step is %.0f m" % [
		coarse_m * 0.001, finest * 0.001, first_step])
	# How much of the sky is open, and whether there is anything above the top
	# of the layer at all.
	#
	# The field is evaluated here the way the shader evaluates it -- the same
	# noise volume from the same seed, the same octaves, the same constants off
	# `CloudShell` -- because the complaint is about what the shader produces
	# and nothing else can answer it. It is a second copy of the arithmetic and
	# it is only a test; the numbers it must agree with are the uniforms.
	var vol := _cloud_volume()
	# What the noise actually looks like, because everything above is a
	# threshold on it. The octaves are summed at the bake and the result
	# stretched there too, so this is the field the shader reads rather than a
	# second copy of it -- and it should now fill its range instead of clustering
	# about its own mean, which is what it did when the stretch was a division
	# in the shader over a field of uniform bytes.
	var nlo := 1e9
	var nhi := -1e9
	var nsum := 0.0
	var nsq := 0.0
	for i in 4000:
		var t0b: float = TAU * float(i) * 0.618034
		var c0: float = 1.0 - 2.0 * (float(i) + 0.5) / 4000.0
		var s0: float = sqrt(maxf(1.0 - c0 * c0, 0.0))
		var u := Vector3(s0 * cos(t0b), c0, s0 * sin(t0b))
		var v: float = _cloud_tex(vol, u * CloudShell.NOISE_SCALE, 0)
		nlo = minf(nlo, v)
		nhi = maxf(nhi, v)
		nsum += v
		nsq += v * v
	var nmean: float = nsum / 4000.0
	var nsd: float = sqrt(maxf(nsq / 4000.0 - nmean * nmean, 0.0))
	print("[cloud] the noise runs %.3f to %.3f, mean %.3f, spread %.3f" % [
		nlo, nhi, nmean, nsd])
	var open_rays := 0
	var sum_a := 0.0
	const RAYS := 240
	for i in RAYS:
		# Spread over the upper hemisphere, from an aeroplane under the layer.
		var t: float = TAU * float(i) * 0.618034
		var c1: float = 0.08 + 0.9 * (float(i) + 0.5) / float(RAYS)
		var sn: float = sqrt(maxf(1.0 - c1 * c1, 0.0))
		var dir := Vector3(sn * cos(t), c1, sn * sin(t)).normalized()
		var a: float = _cloud_alpha(vol, 900.0, dir)
		sum_a += a
		if a < 0.25:
			open_rays += 1
	# ...and flying through it, which is the other half of the complaint: level
	# inside the layer, how much of the way round can you see out?
	var mid: float = (CloudShell.BASE + CloudShell.TOP) * 0.5
	var in_open := 0
	var in_sum := 0.0
	for i in 120:
		var t2: float = TAU * float(i) / 120.0
		var a2: float = _cloud_alpha(vol, mid, Vector3(cos(t2), 0.0, sin(t2)))
		in_sum += a2
		if a2 < 0.25:
			in_open += 1
	print("[cloud] flying level inside the layer: %d of 120 bearings see out, mean opacity %.2f" % [
		in_open, in_sum / 120.0])
	# Straight up from above the top of the layer. There is nothing over it, so
	# this has to be nothing: if it is not, the layer is being drawn where there
	# is no layer and a rocket never sees space.
	var above: float = _cloud_alpha(vol, CloudShell.TOP + 1200.0, Vector3.UP)
	print("[cloud] looking up from 900 m: %d of %d rays see through, mean opacity %.2f" % [
		open_rays, RAYS, sum_a / float(RAYS)])
	print("[cloud] from %.0f m, above the layer, straight up: opacity %.3f" % [
		CloudShell.TOP + 1200.0, above])
	# Every preset, measured. Choosing clear weather has to actually clear the
	# sky: the layer's cover is a threshold on a field that clusters about a
	# half, so before it was stretched, "0.30 cover" and "0.70 cover" were the
	# same overcast and the weather selector did nothing you could see.
	var by_preset: Array = []
	var clear_open := 0
	var overcast_open := 240
	for id in Weather.ids():
		world.weather.apply(String(id), world._env, world._sun, world._fill, world._psm)
		var open_n := 0
		for i in RAYS:
			var t3: float = TAU * float(i) * 0.618034
			var c3: float = 0.08 + 0.9 * (float(i) + 0.5) / float(RAYS)
			var s3: float = sqrt(maxf(1.0 - c3 * c3, 0.0))
			if _cloud_alpha(vol, 900.0,
					Vector3(s3 * cos(t3), c3, s3 * sin(t3)).normalized()) < 0.25:
				open_n += 1
		by_preset.append("%s %d%%" % [String(id),
			int(round(100.0 * float(open_n) / float(RAYS)))])
		if String(id) == "clear":
			clear_open = open_n
		elif String(id) == "overcast":
			overcast_open = open_n
	world.weather.apply(Sim.weather, world._env, world._sun, world._fill, world._psm)
	print("[cloud] open sky by weather: %s" % [
		", ".join(PackedStringArray(by_preset))])
	# The haze, which is the other thing that was white.
	#
	# A depth fade from 24 to 140 km is what atmosphere does when you are
	# standing in it, and it used to be applied at every altitude -- so from a
	# rocket on its way to a satellite, everything beyond 140 km was solid fog
	# colour, which is most of what there is to look at up there.
	# Faded, not switched off. A threshold that disabled the fog outright put a
	# step in the sky at 33 km -- the height where the air falls under two per
	# cent -- because the sky carries some of the fog's colour whatever the
	# depth range says. What is checked is that the haze reaches nothing high
	# up, and does so smoothly.
	var fog_at: Array = []
	var fog_off := false
	for alt in [0.0, 6000.0, 20000.0, 60000.0]:
		world.weather.thin_air(world._env, float(alt))
		fog_at.append("%.0fkm:%.0fkm/%.3f" % [
			float(alt) * 0.001, world._env.fog_depth_begin * 0.001,
			world._env.fog_sky_affect])
		if alt >= 60000.0 and world._env.fog_sky_affect < 0.002:
			fog_off = true
	world.weather.thin_air(world._env, 0.0)
	print("[cloud] the haze begins at, and tints the sky by: %s" % [
		", ".join(PackedStringArray(fog_at))])
	print("[cloud] RESULT: %s" % ("ok" if proxy_ok and sky_off and inside
		and cover > 0.0 and faces.size() > 300
		and drift > 1.0 and drift < 60.0
		# A cloud has to be something you can fly between, and the march has to
		# be able to see the gap.
		and finest > 500.0 and finest < 12000.0
		and first_step < finest * 0.35
		and CloudShell.ERODE > 0.2
		# Sky you can see through, and nothing at all above the layer.
		and open_rays * 4 > RAYS and above < 0.01
		# ...and inside it there has to be somewhere to fly to. This is the
		# white-out: at 88 km to a cloud, not one bearing in a hundred and
		# twenty saw out of the layer.
		and in_open > 12
		# ...and no haze in space.
		and fog_off
		# Choosing the weather has to change the weather.
		and clear_open * 5 > RAYS * 4 and overcast_open * 3 < RAYS
		else "FAILED"))

## The shader's noise volume, which is the very one the shader gets.
##
## Rebuilt from the same seed, it used to be; the octaves are baked into it now
## and rebuilding it here would be a second copy of the rule, which is how a
## harness comes to measure a layer nobody is looking at.
func _cloud_volume() -> PackedByteArray:
	return Sim.native.cloud_volume(CloudShell.VOL_N)

## One trilinear sample of it, repeating, as `filter_linear, repeat_enable`.
## `ch` picks the channel: 0 is the weather system, 1 the clouds within it.
func _cloud_tex(vol: PackedByteArray, p: Vector3, ch: int) -> float:
	var n: int = CloudShell.VOL_N
	var fx: float = p.x * float(n) - 0.5
	var fy: float = p.y * float(n) - 0.5
	var fz: float = p.z * float(n) - 0.5
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var iz := int(floor(fz))
	var tx: float = fx - float(ix)
	var ty: float = fy - float(iy)
	var tz: float = fz - float(iz)
	var acc := 0.0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var gx: int = posmod(ix + dx, n)
				var gy: int = posmod(iy + dy, n)
				var gz: int = posmod(iz + dz, n)
				var wgt: float = (tx if dx == 1 else 1.0 - tx) \
					* (ty if dy == 1 else 1.0 - ty) \
					* (tz if dz == 1 else 1.0 - tz)
				acc += wgt * float(vol[((gz * n + gy) * n + gx) * 2 + ch]) / 255.0
	return acc

func _cloud_density(vol: PackedByteArray, p: Vector3, cover: float,
		dens: float) -> float:
	var r_base: float = Sim.PLANET_R + CloudShell.BASE
	var r_top: float = Sim.PLANET_R + CloudShell.TOP
	var rel: Vector3 = p - Sim.planet_centre
	var r: float = rel.length()
	var up: Vector3 = rel / maxf(r, 1.0)
	var h: float = clampf((r - r_base) / maxf(r_top - r_base, 1.0), 0.0, 1.0)
	var profile: float = smoothstep(0.0, 0.16, h) * (1.0 - smoothstep(0.42, 1.0, h))
	var shape: float = _cloud_tex(vol, up * CloudShell.NOISE_SCALE, 0) \
		* profile - (1.0 - cover)
	if shape <= 0.0:
		return 0.0
	var qd: Vector3 = up * CloudShell.DETAIL_SCALE \
		+ Vector3.ONE * (shape * CloudShell.DETAIL_WARP)
	var detail: float = _cloud_tex(vol, qd, 1)
	return maxf(shape - (1.0 - detail) * CloudShell.ERODE, 0.0) * dens * CloudShell.DENSITY_K

## What the layer does to one ray, as the shader marches it.
func _cloud_alpha(vol: PackedByteArray, alt: float, dir: Vector3) -> float:
	var eye := Sim.planet_centre + Vector3.UP * (Sim.PLANET_R + alt)
	var r_base: float = Sim.PLANET_R + CloudShell.BASE
	var r_top: float = Sim.PLANET_R + CloudShell.TOP
	var hit := func(rad: float) -> Vector2:
		var oc: Vector3 = eye - Sim.planet_centre
		var bq: float = oc.dot(dir)
		var cq: float = oc.dot(oc) - rad * rad
		var disc: float = bq * bq - cq
		if disc < 0.0:
			return Vector2(1.0, -1.0)
		var sq: float = sqrt(disc)
		return Vector2(-bq - sq, -bq + sq)
	var outer: Vector2 = hit.call(r_top)
	var inner: Vector2 = hit.call(r_base)
	if outer.x > outer.y:
		return 0.0
	var t0: float = maxf(outer.x, 0.0)
	var t1: float = outer.y
	if inner.x < inner.y:
		if t0 < inner.x:
			t1 = minf(t1, inner.x)
		else:
			t0 = maxf(t0, inner.y)
	if t1 <= t0:
		return 0.0
	t1 = minf(t1, t0 + 52000.0)
	var cover: float = world.weather.cloud_cover()
	var dens: float = world.weather.cloud_density()
	var span: float = t1 - t0
	var steps: float = float(CloudShell.STEPS)
	var g: float = 1.14 if span > steps * 220.0 else 1.0
	var dt: float = span * (g - 1.0) / (pow(g, steps) - 1.0) if g > 1.0 \
		else span / steps
	var t: float = t0
	var alpha := 0.0
	for i in CloudShell.STEPS:
		if alpha > 0.985:
			break
		var p: Vector3 = eye + dir * (t + dt * 0.5)
		var step_len: float = dt
		t += dt
		dt *= g
		var d: float = _cloud_density(vol, p, cover, dens)
		if d <= 0.0:
			continue
		alpha += (1.0 - exp(-d * step_len * CloudShell.EXTINCTION)) \
			* (1.0 - alpha)
	return alpha
#endregion


#region --globeworld
var _globe_world := false

# The world, on the planet.
func tick_globe_world() -> bool:
	if _globe_world:
		_globe_world = false
		_run_globe_world_test()
		world.get_tree().quit()
		return true
	return false

## The world, on the planet.
##
## This is the test the rewrite lives or dies by. Two things have to be true at
## once, and they pull against each other. The theatre has to survive: the same
## `(x, z)` has to give the same ground it always did, or every road, building,
## airfield and spawn in the game is now in the wrong place. And the rest of the
## planet has to be *there*: ground under you wherever you go, continuous with
## the theatre rather than stepping off a cliff at its edge.
func _run_globe_world_test() -> void:
	# On the country this sortie is flown from. `Vector3.UP` was the
	# chart's origin while the countries were a written-down table sitting
	# near it; they are searched for on the planet's own land now, so `UP`
	# is just a point in an ocean -- and this test duly reported the country
	# the world is built on as 0 % land.
	Sim.set_chart(Sim.home_dir())
	# What the flat world says, before anything is switched over.
	# There is no longer a theatre to compare against.
	#
	# This used to read the same `(x, z)` in both worlds and hold the difference
	# small, because the flat world's authored square was blended into the
	# planet and had to survive the move. The square is gone: the planet is one
	# generated terrain everywhere, so the two worlds are simply different
	# ground and the comparison has nothing to say. What replaced it is below --
	# that the *carving* survived, which is the part that was ever worth
	# keeping, and that the ground it is carved into is land.
	Sim.globe = true
	var worst := 0.0
	# The airfield itself, which everything is built around.
	Sim.globe = false
	var home_flat: float = Sim.height_at(0.0, 0.0)
	Sim.globe = true
	print("[globeworld] at the airfield: flat %.2f m, planet %.2f m" % [
		home_flat, Sim.height_at(0.0, 0.0)])
	# Climate has to be a fact about the place, not about the chart.
	#
	# It was `|z|` over most of the map's half width -- a function of where the
	# chart is centred -- so the same ground changed climate when the chart
	# moved under it, and the ground's colour with it. Read the same *places*
	# from two charts and they have to answer the same.
	var spots: Array = []
	for i0 in 60:
		var a0: float = TAU * float(i0) / 60.0
		for km0 in [40.0, 200.0]:
			var q0 := Vector2(cos(a0), sin(a0)) * (float(km0) * 1000.0)
			spots.append([Sim.chart_to_dir(q0.x, q0.y),
				Sim.climate_lat(q0.x, q0.y),
				Sim.biomes.kind(q0.x, q0.y, Sim.height_at(q0.x, q0.y), 1.0),
				Sim.height_at(q0.x, q0.y) - Sim.sea_at(q0.x, q0.y)])
	# The whole move, as the game does it: the chart and the world's works with
	# it. Moving the chart alone leaves the roads and the aerodrome behind and
	# the ground under a place then carries somebody else's earthworks.
	var o1: Vector3 = Sim.chart_origin
	var e1: Vector3 = Sim.chart_east
	var s1: Vector3 = Sim.chart_south
	Sim.set_chart(Sim.chart_to_dir(130_000.0, 70_000.0))
	Sim.rechart_world(o1, e1, s1)
	var drift := 0.0
	var biome_moved := 0
	var hgt_worst := 0.0
	for sp in spots:
		var spp: Array = sp
		var q2: Vector2 = Sim.dir_to_chart(spp[0])
		drift = maxf(drift, absf(Sim.climate_lat(q2.x, q2.y) - float(spp[1])))
		# What the ground itself says, which is the claim being made: read from
		# two charts, the same place has to be the same height. The biome label
		# is a threshold on that height, so at a shoreline two readings a
		# fraction of a metre apart fall either side of it and the label flips
		# without anything having moved -- both of the ones this caught were in
		# a river channel, agreeing to half a metre and disagreeing about
		# whether that made them sand or forest. A label that changes while the
		# ground under it does not is the thresholding, not the world.
		var h2: float = Sim.height_at(q2.x, q2.y) - Sim.sea_at(q2.x, q2.y)
		hgt_worst = maxf(hgt_worst, absf(h2 - float(spp[3])))
		if Sim.biomes.kind(q2.x, q2.y, Sim.height_at(q2.x, q2.y), 1.0) \
				!= String(spp[2]) and absf(h2 - float(spp[3])) > 0.5:
			biome_moved += 1
	print("[globeworld] read from the moved chart, the same ground stands within %.2f m of where it did" % [
		hgt_worst])
	var o2: Vector3 = Sim.chart_origin
	var e2: Vector3 = Sim.chart_east
	var s2b: Vector3 = Sim.chart_south
	Sim.set_chart(Sim.home_dir())
	Sim.rechart_world(o2, e2, s2b)
	# and it has to actually vary, or the whole planet is one climate
	var cold: float = Sim.climate_lat(0.0, -1_400_000.0)
	var warm: float = Sim.climate_lat(0.0, 0.0)
	print("[globeworld] climate: %.4f at the airfield, %.4f 1400 km toward the chart's north; read from a chart 150 km away it moves by %.4f, and %d of %d places changed biome" % [
		warm, cold, drift, biome_moved, spots.size()])
	# The world's works have to be on land. The aerodrome, the roads and every
	# town the router laid out are at fixed places on the chart, and a planet
	# generated without regard to them has no reason to put land there -- so it
	# is asked to, and this is the check that it did.
	var home_land := 0
	var home_n := 0
	for i0 in 64:
		var a0: float = TAU * float(i0) / 64.0
		for km0 in [20.0, 80.0, 160.0, 260.0]:
			var q0 := Vector2(cos(a0), sin(a0)) * (float(km0) * 1000.0)
			home_n += 1
			if Sim.height_at(q0.x, q0.y) > Sim.sea_at(q0.x, q0.y):
				home_land += 1
	print("[globeworld] the country the world is built on is %d%% land out to 260 km" % [
		int(round(100.0 * float(home_land) / maxf(float(home_n), 1.0)))])
	# Out past the edge of the authored world there has to be ground, and it has
	# to be ground rather than a constant.
	var out_lo := 1e9
	var out_hi := -1e9
	var land := 0
	var total := 0
	for i3 in 64:
		var a3: float = TAU * float(i3) / 64.0
		for km3 in [1500.0, 4000.0, 9000.0, 15000.0]:
			var q := Vector2(cos(a3), sin(a3)) * (float(km3) * 1000.0)
			var h: float = Sim.height_at(q.x, q.y)
			var sea: float = Sim.sea_at(q.x, q.y)
			total += 1
			if h > sea:
				land += 1
			out_lo = minf(out_lo, h - sea)
			out_hi = maxf(out_hi, h - sea)
	print("[globeworld] out on the rest of the planet: %d%% land, from %.0f m to %.0f m above its own sea" % [
		int(round(100.0 * float(land) / maxf(float(total), 1.0))), out_lo, out_hi])
	# There is no join to walk across any more.
	#
	# This used to walk out through the blend between the authored square and
	# the generated planet and hold the biggest 2 km step against the flat
	# world's own worst over the same ground. With the square gone the ground is
	# one field the whole way, so what it measures now is whether the planet has
	# mountains on it -- it does, and a 437 m step in two kilometres is one of
	# them rather than a seam.
	# And the chart can be moved: stand somewhere else and there is ground there.
	Sim.set_chart(Vector3(0.42, 0.55, -0.72).normalized())
	var far_lo := 1e9
	var far_hi := -1e9
	for i4 in 24:
		var a4: float = TAU * float(i4) / 24.0
		for km4 in [1.0, 50.0, 300.0]:
			var q4 := Vector2(cos(a4), sin(a4)) * (float(km4) * 1000.0)
			var h4: float = Sim.height_at(q4.x, q4.y) - Sim.sea_at(q4.x, q4.y)
			far_lo = minf(far_lo, h4)
			far_hi = maxf(far_hi, h4)
	print("[globeworld] standing somewhere else entirely, the ground runs %.0f m to %.0f m above sea" % [
		far_lo, far_hi])
	# And the ground actually builds there. Everything above measures the field;
	# this measures the mesh, which is the thing you land on.
	world.terrain.recentre(Vector3(0.0, 3000.0, 0.0), true)
	world.terrain.flush_pending()
	var chunks: int = int(world.terrain.stats.get("chunks", 0))
	var drawn_worst := 0.0
	for i5 in 40:
		var a5: float = TAU * float(i5) / 40.0
		var q5 := Vector2(cos(a5), sin(a5)) * 6000.0
		drawn_worst = maxf(drawn_worst, absf(
			Terrain.surface_height(q5.x, q5.y) - Sim.height_at(q5.x, q5.y)))
	print("[globeworld] built %d chunks on the far side of the planet; the drawn surface is within %.2f m of the field" % [
		chunks, drawn_worst])
	# The floating origin: move the chart a long way and see whether the world
	# came with it. What has to survive is height above the ground -- an
	# aeroplane at 3000 ft has to still be at 3000 ft, not buried or in orbit.
	Sim.set_chart(Sim.home_dir())
	var probe := AIPlane.new()
	probe.setup("f16")
	probe.team = 0
	world.add_child(probe)
	probe.global_position = Vector3(90_000.0, 0.0, 40_000.0)
	probe.global_position.y = Sim.height_at(90_000.0, 40_000.0) + 3000.0
	var agl_before: float = probe.global_position.y \
		- Sim.height_at(probe.global_position.x, probe.global_position.z)
	var dir_before: Vector3 = Sim.chart_to_dir(
		probe.global_position.x, probe.global_position.z)
	# a quarter of the way round the planet
	world.chart_follow.rechart(Sim.chart_to_dir(0.0, -10_000_000.0))
	var agl_after: float = probe.global_position.y \
		- Sim.height_at(probe.global_position.x, probe.global_position.z)
	var dir_after: Vector3 = Sim.chart_to_dir(
		probe.global_position.x, probe.global_position.z)
	var moved: float = dir_before.angle_to(dir_after) * Sim.PLANET_R
	print("[globeworld] chart moved 10000 km: the aeroplane kept %.1f m of %.1f m above ground, and stayed within %.0f m of the same ground" % [
		agl_after, agl_before, moved])
	probe.queue_free()
	Sim.set_chart(Sim.home_dir())
	Sim.globe = false
	# The step is gated against the flat world's own worst over the same walk,
	# not against a number written down here: the theatre has mountains and a
	# 2 km step across a ridge is terrain, not a seam.
	print("[globeworld] RESULT: %s" % ("ok" if worst < 60.0 and land > 4
		and chunks > 40 and drawn_worst < 25.0
		and home_land * 100 > home_n * 55
		# A real gradient, not a large one. The squeeze is 1.15 -- sized so the
		# planet's ice covers 30 per cent rather than 89 -- so 1400 km north of
		# the equator is a quarter of the way to polar, and that is the number
		# this is asking to see rather than the 0.3 a harder squeeze gave.
		# A gradient, in whichever direction. This asked for the ground 1400 km
		# north to be colder, which is true in the northern hemisphere and the
		# opposite in the southern -- and the countries are searched for on the
		# planet's land now, so which hemisphere yours is in is not something
		# the test gets to assume.
		and drift < 0.002 and absf(cold - warm) > 0.15 and biome_moved == 0
		and hgt_worst < 1.0
		and absf(agl_after - agl_before) < 30.0 and moved < 2000.0
		and land < total and out_hi > 500.0
		and far_hi - far_lo > 200.0
		# The airfield is carved to the height it was registered at, and both
		# frames read it. This asked for 0.0 for as long as `RUNWAY_ELEV`
		# pinned the home strip to sea level; the strip now stands on whatever
		# ground its country has, so what is worth checking is that the carving
		# is there and both frames agree on it -- not the particular number.
		and absf(home_flat - float(Sim.fields[0]["elev"])) < 0.01
		else "FAILED"))
#endregion


#region --charttest
var _chart_test := false

# The chart the whole world is about to be re-founded on.
func tick_chart() -> bool:
	if _chart_test:
		_chart_test = false
		_run_chart_test()
		world.get_tree().quit()
		return true
	return false

## The surface chart, which every other spherical thing is going to be built on.
##
## Three properties have to hold before anything is founded on it. It has to be
## an exact inverse, or a position written by one subsystem is read back wrong by
## the next. Distances along the ground from the middle of it have to be true,
## because every range readout and weapon envelope in the game is a distance in
## chart coordinates. And with the origin at the theatre it has to reproduce the
## world that is already there, or moving to it is a rewrite rather than a
## re-founding.
func _run_chart_test() -> void:
	Sim.set_chart(Vector3.UP)
	# Round trip, out to the far corner of the world and well beyond it.
	var worst_rt := 0.0
	var worst_at := Vector2.ZERO
	for i in 64:
		var a: float = TAU * float(i) / 64.0
		for km in [1.0, 40.0, 200.0, 600.0, 900.0, 2000.0, 6000.0]:
			var p := Vector2(cos(a), sin(a)) * (float(km) * 1000.0)
			var back: Vector2 = Sim.dir_to_chart(Sim.chart_to_dir(p.x, p.y))
			var e: float = back.distance_to(p)
			if e > worst_rt:
				worst_rt = e
				worst_at = p
	# The floor here is the float: a unit vector in single precision resolves
	# about 1e-7, which at the planet's radius is two thirds of a metre. That
	# number is the reason this chart exists at all -- positions on a planet
	# cannot be carried in world coordinates and still have centimetres in them,
	# so they are carried as offsets from somewhere near you instead.
	print("[chart] round trip is out by at most %.3f m, at %.0f km (the single-precision floor is %.2f m)" % [
		worst_rt, worst_at.length() * 0.001, Sim.PLANET_R * 1.0e-7])
	# Distance along the ground from the origin, against what the chart says.
	var worst_d := 0.0
	for km2 in [10.0, 100.0, 600.0, 1500.0, 5000.0]:
		var want: float = float(km2) * 1000.0
		var d: Vector3 = Sim.chart_to_dir(want, 0.0)
		# The great-circle distance the chart claims to be measuring, taken the
		# stable way. Read with acos this check reported 243 m of error at
		# 10 km, which was the check's own arithmetic and not the chart's: acos
		# of a cosine within a float's last digit of 1 has no digits left.
		var par: float = d.dot(Sim.chart_origin)
		var perp: float = (d - Sim.chart_origin * par).length()
		worst_d = maxf(worst_d, absf(atan2(perp, par) * Sim.PLANET_R - want))
	print("[chart] ground distance from the middle is out by at most %.3f m over 5000 km" % worst_d)
	# With the origin at the theatre it has to be the world that is already here.
	var worst_old := 0.0
	for i2 in 48:
		var a2: float = TAU * float(i2) / 48.0
		for km3 in [5.0, 60.0, 300.0, 600.0]:
			var p2 := Vector2(cos(a2), sin(a2)) * (float(km3) * 1000.0)
			# What the flat world means by this pair: the point straight out
			# there on the cap.
			var d2: Vector3 = Sim.chart_to_dir(p2.x, p2.y)
			var flat := Vector3(p2.x, sqrt(maxf(Sim.PLANET_R * Sim.PLANET_R
				- p2.length_squared(), 0.0)), p2.y).normalized()
			worst_old = maxf(worst_old, d2.distance_to(flat) * Sim.PLANET_R)
	# Not zero, and not a fault: the flat world reads the pair as a *projected*
	# offset and the chart reads it as a distance along the ground, which differ
	# by R(theta - sin theta). Nothing stored moves -- positions are kept as the
	# pair -- so this is the size of the reinterpretation, not of an error.
	print("[chart] against the flat world it replaces, the same pair lands %.0f m away at worst over 600 km (the projection difference, R(t - sin t))" % worst_old)
	# Somewhere else entirely: the chart has to work off the theatre too, which
	# is the whole point of having one.
	Sim.set_chart(Vector3(0.3, 0.2, -0.93).normalized())
	var far_rt := 0.0
	for i3 in 32:
		var a3: float = TAU * float(i3) / 32.0
		var p3 := Vector2(cos(a3), sin(a3)) * 400_000.0
		far_rt = maxf(far_rt, Sim.dir_to_chart(
			Sim.chart_to_dir(p3.x, p3.y)).distance_to(p3))
	# and the chart must still be the right way up: south has to point south
	var south_lat: float = Sim.latitude_at(0.0, 0.0)
	var d_south: Vector3 = Sim.chart_to_dir(0.0, 100_000.0)
	var lat_south: float = asin(clampf(d_south.dot(Sim.PLANET_NORTH), -1.0, 1.0))
	var lat_home: float = asin(clampf(
		Sim.chart_origin.dot(Sim.PLANET_NORTH), -1.0, 1.0))
	print("[chart] moved off the theatre: round trip out by %.3f m, and going south loses %.3f deg of latitude" % [
		far_rt, rad_to_deg(lat_home - lat_south)])
	Sim.set_chart(Vector3.UP)
	print("[chart] RESULT: %s" % ("ok" if worst_rt < 1.0 and worst_d < 1.0
		and worst_old < 1200.0 and far_rt < 1.0
		and lat_home - lat_south > 0.0 and absf(south_lat) < 1e-6
		else "FAILED"))
#endregion


#region --maptest
var _map_test := false

# What the map has to draw, across the whole extent it claims to cover.
func tick_map() -> bool:
	if _map_test:
		_map_test = false
		_run_map_test()
		world.get_tree().quit()
		return true
	return false

## How much world there is, across the full extent the map claims to cover.
##
## The map is drawn over +-600 km and the terrain root reaches +-983 km. If the
## ground only exists near the airfield then both the chart and the globe are
## correctly drawing a world that is mostly empty, and the thing to fix is the
## world; if the ground is there and the map is not showing it, the fault is in
## the drawing. This says which.
func _run_map_test() -> void:
	# Land by distance from the airfield, on the field itself rather than
	# through the map's own bake, so the two can be compared.
	var rings := [20_000.0, 60_000.0, 120_000.0, 250_000.0, 400_000.0,
		600_000.0, 900_000.0]
	var prev := 0.0
	for r in rings:
		var rr: float = r
		var land := 0
		var total := 0
		for i in 96:
			var a: float = TAU * float(i) / 96.0
			for k in 6:
				var d: float = lerpf(prev, rr, (float(k) + 0.5) / 6.0)
				var p := Vector2(cos(a) * d, sin(a) * d)
				total += 1
				if Sim.height_at(p.x, p.y) > Sim.sea_at(p.x, p.y):
					land += 1
		print("[map] out to %4.0f km: %3d%% land" % [
			rr * 0.001, int(round(100.0 * float(land) / maxf(float(total), 1.0)))])
		prev = rr
	# And what the baked image actually holds, which is what both views draw.
	var st: Dictionary = world.map.map_stats
	var land_px := int(st.get("land", 0))
	var sea_px := int(st.get("sea", 0))
	var px: int = land_px + sea_px
	print("[map] the relief bake is %d x %d over +-%.0f km: %d%% of it is land" % [
		int(st.get("res", 0)), int(st.get("res", 0)), MapView.HALF * 0.001,
		int(round(100.0 * float(land_px) / maxf(float(px), 1.0)))])
	# The furthest land in each of the four directions, so a map that is drawing
	# a small square in the middle of nothing can be told from a world that is
	# a small square in the middle of nothing.
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2(0, 1), Vector2(0, -1)]:
		var dir: Vector2 = d
		var far := 0.0
		for k in 900:
			var q: Vector2 = dir * (float(k) * 1000.0)
			if Sim.height_at(q.x, q.y) > Sim.sea_at(q.x, q.y):
				far = float(k) * 1000.0
		print("[map] furthest land toward %s: %.0f km" % [str(dir), far * 0.001])
	# Written out, because the fastest way to tell a map that is drawing the
	# world badly from a world that is badly drawn is to look at the image.
	world.map.relief().get_image().save_png("user://map_relief.png")
	if is_instance_valid(world.planet) and world.planet.sheet != null:
		world.planet.sheet.get_image().save_png("user://planet_sheet.png")
	world.map.detail().get_image().save_png("user://map_detail.png")
	print("[map] relief written to %s" % ProjectSettings.globalize_path(
		"user://map_relief.png"))
	# What the map can actually resolve at the zoom it opens at, which is the
	# number that decides whether it looks like ground or like one smear.
	var across: float = 1080.0 / (1080.0 * 0.86 * 29.0 / (MapView.HALF * 2.0))
	for sheet in [["world", MapView.HALF, MapView.RES],
			["close-in", MapView.DETAIL_HALF, MapView.DETAIL_RES]]:
		var sh: Array = sheet
		var m_per: float = float(sh[1]) * 2.0 / float(sh[2])
		print("[map] %s sheet: %d px over +-%.0f km, %.0f m a texel, %.0f texels across the opening view" % [
			String(sh[0]), int(sh[2]), float(sh[1]) * 0.001, m_per, across / m_per])
	# How the six nationalities are laid out: what share each holds, and how big
	# a piece of it you cross before the flag changes. The share was fixed once
	# already; the size of the blocks is a separate question and this measures
	# it, by walking lines across the world and counting how far a run of one
	# flag lasts.
	var share: Dictionary = {}
	var runs: Array = []
	# Territory has to belong to the planet, not to the chart: the same ground
	# must answer the same way however the chart is placed over it. Checked by
	# reading a fixed set of *places* twice, from two different charts.
	var chart_bound := 0
	if Sim.globe:
		var places: Array = []
		for i in 200:
			var a: float = TAU * float(i) / 200.0
			var q := Vector2(cos(a), sin(a)) * 90_000.0
			places.append([Sim.chart_to_dir(q.x, q.y),
				Sim.region_faction(q.x, q.y)])
		Sim.set_chart(Sim.chart_to_dir(140_000.0, 60_000.0))
		for pl in places:
			var pp: Array = pl
			var q2: Vector2 = Sim.dir_to_chart(pp[0])
			if Sim.region_faction(q2.x, q2.y) != String(pp[1]):
				chart_bound += 1
		Sim.set_chart(Vector3.UP)
		print("[map] of 200 places read from two different charts, %d changed nationality" % chart_bound)
	var step := 4000.0
	for line in 40:
		var z: float = lerpf(-Sim.WORLD_HALF, Sim.WORLD_HALF, float(line) / 39.0)
		var last := ""
		var run := 0.0
		var k := 0
		while k < 300:
			var x: float = lerpf(-Sim.WORLD_HALF, Sim.WORLD_HALF, float(k) / 299.0)
			var f: String = Sim.region_faction(x, z)
			share[f] = int(share.get(f, 0)) + 1
			if f == last:
				run += step
			else:
				if last != "":
					runs.append(run)
				last = f
				run = step
			k += 1
		runs.append(run)
	runs.sort()
	var total_s := 0
	for v in share.values():
		total_s += int(v)
	var line_out := PackedStringArray()
	for f2 in share.keys():
		line_out.append("%s %d%%" % [String(f2),
			int(round(100.0 * float(share[f2]) / maxf(float(total_s), 1.0)))])
	print("[map] nationalities: %s" % ", ".join(line_out))
	var mean_run := 0.0
	for r2 in runs:
		mean_run += float(r2)
	mean_run /= maxf(float(runs.size()), 1.0)
	print("[map] a run of one flag lasts %.0f km on average, median %.0f km, longest %.0f km" % [
		mean_run * 0.001, float(runs[int(runs.size() / 2.0)]) * 0.001,
		float(runs[runs.size() - 1]) * 0.001])
	# The map must own the pointer while it is up, or the camera takes it:
	# freelook is on CMD and so is the objective marker, and a captured cursor
	# sits in the middle of the screen where the marker cannot be aimed.
	var was_open: bool = world.map.visible
	if not world.map.visible:
		world.map.toggle()
	var claimed: bool = Sim.ui_pointer
	world.map.toggle()
	var released: bool = not Sim.ui_pointer
	if was_open:
		world.map.toggle()
	print("[map] with the map up the pointer is claimed: %s; with it down, released: %s" % [
		str(claimed), str(released)])
	# A map you cannot read is a map that is not working, so that is what is
	# gated: enough texels across the view it opens at to show ground.
	var best: float = across / (MapView.DETAIL_HALF * 2.0 / float(MapView.DETAIL_RES))
	print("[map] RESULT: %s" % ("ok" if px > 0 and best > 200.0
		and claimed and released
		else "FAILED — %.0f texels across the opening view" % best))
#endregion


#region --globetest
var _globe_test := false

# The map drawn on the planet.
func tick_globe() -> bool:
	if _globe_test:
		_globe_test = false
		_run_globe_test()
		world.get_tree().quit()
		return true
	return false

func _run_globe_test() -> void:
	var m := world.map
	if m == null:
		print("[globe] RESULT: FAILED — no map")
		return
	m.globe = true
	m.globe_spin = 0.0
	m.globe_tilt = 0.0
	m.globe_zoom = 1.0
	var org := Vector2(960.0, 540.0)
	var rad := 450.0
	var b: Basis = m.globe_view.call("_globe_basis")
	# The middle of the chart, which is the country this sortie is flown from
	# and what the map should open looking at.
	var home: Vector3 = m.globe_view.call("_globe_at", Vector2.ZERO, org, rad, b, 1.0)
	var home_off: float = Vector2(home.x, home.y).distance_to(org)
	print("[globe] the airfield lands %.2f px from the middle, facing %.3f" % [
		home_off, home.z])
	# A corner of the mapped square, which is 848 km out: it should be a little
	# way off the middle and still on the near side.
	var corner: Vector3 = m.globe_view.call("_globe_at",
		Vector2(Sim.WORLD_HALF, Sim.WORLD_HALF), org, rad, b, 1.0)
	var corner_off: float = Vector2(corner.x, corner.y).distance_to(org)
	# Where it ought to be: the ball is `rad` px for a radius of PLANET_R, and
	# the corner stands 848 km off the axis.
	var want: float = Vector2(Sim.WORLD_HALF, Sim.WORLD_HALF).length() \
		/ Sim.PLANET_R * rad
	print("[globe] the corner of the theatre lands %.2f px out, against %.2f expected" % [
		corner_off, want])
	# The far side. There is no ground there, but the projection has to say so
	# rather than folding it onto the front.
	var back_dir: Vector3 = -Sim.chart_origin
	var back: Vector3 = b * back_dir
	print("[globe] the antipode faces %.3f (negative is away from the eye)" % back.z)
	# Turn it half over and the theatre should go round the back.
	m.globe_tilt = PI * 0.49
	var b2: Basis = m.globe_view.call("_globe_basis")
	var turned: Vector3 = m.globe_view.call("_globe_at", Vector2.ZERO, org, rad, b2, 1.0)
	print("[globe] tilted %.0f deg, the airfield faces %.3f" % [
		rad_to_deg(m.globe_tilt), turned.z])
	# The airfield has to be on the equator, not at a pole: the climate has run
	# its bands along z since long before there was a planet to put them on.
	var lat_home: float = Sim.latitude_at(0.0, 0.0)
	var lat_north: float = Sim.latitude_at(0.0, -Sim.WORLD_HALF)
	var lat_corner: float = Sim.latitude_at(Sim.WORLD_HALF, 0.0)
	print("[globe] the airfield is at %.3f deg; the top of the chart is %.2f deg, and due east of the airfield is %.3f deg" % [
		rad_to_deg(lat_home), rad_to_deg(lat_north), rad_to_deg(lat_corner)])
	# Where the world lands on the planet. The airfield has to come out at the
	# middle of the relief image, one world east has to come out at its edge,
	# and the whole sphere has to be covered rather than one square of it.
	# The sheet's own frame: north, the prime meridian, and east off it. The
	# thing being *looked at* is the chart's origin, which is a country and no
	# longer the same direction as the meridian the sheet is indexed from.
	var pole: Vector3 = Sim.PLANET_NORTH
	var mid := Vector3.UP
	var east: Vector3 = pole.cross(mid).normalized()
	var uv_home: Vector2 = m.call("_globe_uv", Sim.chart_origin, pole, mid, east)
	var e_dir: Vector3 = Sim.chart_to_dir(Sim.WORLD_HALF, 0.0)
	var uv_east: Vector2 = m.call("_globe_uv", e_dir, pole, mid, east)
	var n_dir: Vector3 = Sim.chart_to_dir(0.0, -Sim.WORLD_HALF)
	var uv_north: Vector2 = m.call("_globe_uv", n_dir, pole, mid, east)
	# Plain equirectangular over the generated planet: half the world's width is
	# that fraction of the way round the equator, and half its height that
	# fraction of the way to the pole. Worked out rather than written down, so
	# the test cannot go stale when the planet changes size.
	# Meridians converge, so the same distance east is more longitude the
	# further from the equator it is measured.
	var ang: float = Sim.WORLD_HALF / Sim.PLANET_R
	var lat0: float = asin(clampf(Sim.chart_origin.dot(pole), -1.0, 1.0))
	var want_e: float = uv_home.x + (ang / TAU) / maxf(cos(lat0), 1e-6)
	var want_n: float = uv_home.y - ang / PI
	print("[globe] the middle of the chart lands at uv %s; half a world east at %s (want %.3f); half a world north at %s (want %.3f)" % [
		str(uv_home.snapped(Vector2.ONE * 0.001)),
		str(uv_east.snapped(Vector2.ONE * 0.001)), want_e,
		str(uv_north.snapped(Vector2.ONE * 0.001)), want_n])
	print("[globe] the theatre is %.1f%% of the way round the equator; the rest of the planet is generated" % (
		100.0 * (Sim.WORLD_HALF * 2.0) / (TAU * Sim.PLANET_R)))
	# Nothing may land outside the disc: a projection that runs away at the limb
	# is the classic way to get this wrong, and it draws the world as a smear.
	var worst := 0.0
	for i in 64:
		for j in 16:
			var a := TAU * float(i) / 64.0
			var r: float = Sim.PLANET_R * 0.999 * float(j) / 15.0
			var p: Vector3 = m.globe_view.call("_globe_at",
				Vector2(cos(a) * r, sin(a) * r), org, rad, b, 1.0)
			worst = maxf(worst, Vector2(p.x, p.y).distance_to(org))
	print("[globe] the furthest any ground point lands is %.1f px, on a %.0f px disc" % [
		worst, rad])
	m.globe = false
	print("[globe] RESULT: %s" % ("ok" if home_off < 0.01 and home.z > 0.99
		and absf(corner_off - want) < 1.0 and corner.z > 0.99 and back.z < -0.99
		and turned.z < 0.05 and worst <= rad + 0.5
		and absf(lat_home) < 1e-6 and lat_north > 0.05
		and absf(lat_corner) < 1e-6
		and absf(uv_east.x - want_e) < 0.002
		and absf(uv_east.y - uv_home.y) < 0.002
		and absf(uv_north.y - want_n) < 0.002
		and absf(uv_north.x - uv_home.x) < 0.002
		else "FAILED"))
#endregion


#region --patchtest
var _patch_test := false

# ...and whether it gets finer as it is zoomed.
func tick_patch() -> bool:
	if _patch_test:
		_patch_test = false
		await _run_patch_test()
		world.get_tree().quit()
		return true
	return false

func _run_patch_test() -> void:
	var m := world.map
	if m == null:
		print("[patch] RESULT: FAILED — no map")
		return
	m.globe = true
	m.globe_spin = 0.0
	m.globe_tilt = 0.0
	var vp: Vector2 = m.get_viewport_rect().size
	var half: float = minf(vp.x, vp.y) * 0.5
	var spans: Array = []
	var last := 1e9
	var shrinks := true
	for z in [1.0, 4.0, 20.0, 80.0, 260.0]:
		m.globe_zoom = float(z)
		var rad: float = half * 0.84 * float(z)
		var b: Basis = m.globe_view.call("_globe_basis")
		var w: PackedFloat32Array = m.globe_view.call("_globe_window", rad, b)
		if w.size() != 4:
			spans.append("x%.0f:whole" % float(z))
			continue
		var vspan: float = (w[3] - w[2]) * 180.0
		spans.append("x%.0f:%.3f deg" % [float(z), vspan])
		if vspan >= last:
			shrinks = false
		last = vspan
	print("[patch] the window the map bakes, by zoom: %s" % [
		", ".join(PackedStringArray(spans))])
	# What one texel of each is worth on the ground, at the closest zoom.
	m.globe_zoom = 260.0
	var b2: Basis = m.globe_view.call("_globe_basis")
	var rad2: float = half * 0.84 * 260.0
	var win: PackedFloat32Array = m.globe_view.call("_globe_window", rad2, b2)
	var ok_win: bool = win.size() == 4
	var base_m := 0.0
	var patch_m := 0.0
	var ms := 0.0
	var agree := 0.0
	var asked_ms := 0.0
	if ok_win:
		# What the main thread pays, and what the bake costs. They used to be
		# the same number: the map baked in line and the frame that zoomed
		# stopped for it.
		var t0 := Time.get_ticks_usec()
		m.globe_view.call("_want_patch", win)
		asked_ms = float(Time.get_ticks_usec() - t0) * 0.001
		var spun := 0
		while not Sim.native.patch_ready() and spun < 4000:
			spun += 1
			await world.get_tree().process_frame
		m.globe_view.call("_collect_patch")
		ms = float(m.get("_patch_ms"))
		# Metres to a texel: the base sheet spans the planet, the patch spans
		# the window.
		var sheet_h: float = float(Planet.SHEET_H)
		base_m = PI * Sim.PLANET_R / sheet_h
		patch_m = (win[3] - win[2]) * PI * Sim.PLANET_R / float(m.PATCH_RES)
		# Same world: the middle of the patch has to be the ground that is
		# actually there, not a second generation of it.
		var pole: Vector3 = Sim.PLANET_NORTH
		var home := Vector3.UP
		var east: Vector3 = pole.cross(home).normalized()
		var cu: float = (win[0] + win[1]) * 0.5
		var cv: float = (win[2] + win[3]) * 0.5
		var d: Vector3 = m.globe_view.call("_uv_dir", cu, cv, pole, home, east)
		var q: Vector2 = Sim.dir_to_chart(d)
		agree = absf(Sim.native.planet_height(d)
			- (Sim.height_at(q.x, q.y) - Sim.sea_at(q.x, q.y)))
	print("[patch] at the closest zoom a texel is %.0f m on the base sheet and %.0f m on the patch" % [
		base_m, patch_m])
	print("[patch] baking it took %.1f ms, of which %.2f ms on the main thread; the middle of it agrees with the ground to %.2f m" % [
		ms, asked_ms, agree])
	# Are the roads on it?
	#
	# A carriageway is twelve metres wide and the patch is 234 m to a texel, so
	# a road drawn to scale is invisible and the planet map had none on it. They
	# are inked into the bake a texel or so wide, which is how a road is drawn
	# on any map. This compares a texel the network runs through against one two
	# kilometres off it: if the ink is landing, the two are different colours.
	var ink_delta := 0.0
	var on_road := Vector2.ZERO
	if ok_win and m.get("_patch_tex") != null:
		var img: Image = (m.get("_patch_tex") as ImageTexture).get_image()
		var pole2: Vector3 = Sim.PLANET_NORTH
		var home2 := Vector3.UP
		var east2: Vector3 = pole2.cross(home2).normalized()
		var w2: PackedFloat32Array = m.get("_patch_win")
		var to_px := func(q: Vector2) -> Vector2i:
			var uv: Vector2 = m.call("_globe_uv",
				Sim.chart_to_dir(q.x, q.y), pole2, home2, east2)
			return Vector2i(
				int((uv.x - w2[0]) / maxf(w2[1] - w2[0], 1e-9) * float(m.PATCH_RES)),
				int((uv.y - w2[2]) / maxf(w2[3] - w2[2], 1e-9) * float(m.PATCH_RES)))
		# A point the network actually runs through, near the middle of the
		# window, and its neighbour well off the road.
		for ln in Sim.roads.road_lines():
			var pl: PackedVector2Array = ln
			for pt in pl:
				var px: Vector2i = to_px.call(pt)
				if px.x < 4 or px.y < 4 or px.x >= m.PATCH_RES - 4 \
						or px.y >= m.PATCH_RES - 4:
					continue
				var off: Vector2i = to_px.call(pt + Vector2(2000.0, 0.0))
				if off.x < 0 or off.y < 0 or off.x >= m.PATCH_RES \
						or off.y >= m.PATCH_RES:
					continue
				var ca: Color = img.get_pixel(px.x, px.y)
				var cb: Color = img.get_pixel(off.x, off.y)
				var dd: float = absf(ca.r - cb.r) + absf(ca.g - cb.g) \
					+ absf(ca.b - cb.b)
				if dd > ink_delta:
					ink_delta = dd
					on_road = pt
			if ink_delta > 0.2:
				break
	print("[patch] the road ink shows as %.3f of colour between a texel on the network at %s and one 2 km off it" % [
		ink_delta, str(on_road.round())])
	# The mesh, which is rebuilt every frame the map is open.
	m.globe_zoom = 1.0
	var b3: Basis = m.globe_view.call("_globe_basis")
	var lit3: Vector3 = m.globe_view.call("_globe_light", b3)
	var org3 := Vector2(960.0, 540.0)
	var rad3 := 450.0
	var t1 := Time.get_ticks_usec()
	var mesh: Array = Sim.native.globe_mesh(m.GLOBE_RINGS, m.GLOBE_SEGS,
		org3, rad3, b3, lit3)
	var mesh_ms: float = float(Time.get_ticks_usec() - t1) * 0.001
	var pts: PackedVector2Array = mesh[0]
	var idx3: PackedInt32Array = mesh[3]
	# Every point has to be on the disc the globe is drawn in, or the mesh and
	# the marks drawn over it are using different projections -- which is the
	# one thing that can go wrong when a picture is built on one side of the
	# binding and annotated on the other.
	var off_disc := 0
	for p3 in pts:
		if (p3 as Vector2).distance_to(org3) > rad3 + 0.5:
			off_disc += 1
	# ...and the mesh has to agree with the projection the marks use. The
	# sub-observer point is the middle of the disc in both.
	var centre_dir: Vector3 = (b3.inverse() * Vector3(0.0, 0.0, 1.0)).normalized()
	var q3: Vector2 = Sim.dir_to_chart(centre_dir)
	var mark: Vector3 = m.globe_view.call("_globe_at", q3, org3, rad3, b3, 1.0)
	var mark_off: float = Vector2(mark.x, mark.y).distance_to(org3)
	print("[patch] the globe mesh is %d triangles in %.2f ms; %d points off the disc; the marks project to %.2f px of its middle" % [
		int(idx3.size() / 3.0), mesh_ms, off_disc, mark_off])
	var ok: bool = shrinks and ok_win and patch_m < base_m * 0.1 \
		and agree < 1.0 and ms < 400.0 and asked_ms < 2.0 \
		and idx3.size() > 3000 and off_disc == 0 and mark_off < 1.0 \
		and mesh_ms < 8.0 and ink_delta > 0.05
	print("[patch] RESULT: %s" % ("ok" if ok else "FAILED"))
#endregion


#region --airtest
var _air_test := false

func tick_air() -> bool:
	if _air_test:
		_air_test = false
		_run_air_test()
		world.get_tree().quit()
		return true
	return false

## The atmosphere, as a function of where you are looking from.
##
## The claim is that the air thins out from under you as you climb, so that a
## rocket on its way to a satellite flies out of the blue and into space. This
## evaluates the shell's own opacity the way the shader does -- the same column
## integral, the same two normalisers, the same night-side gate -- and reports
## what it comes to at a set of altitudes. It is a second copy of the
## arithmetic and it is only a test; the constants come off `Atmosphere`.
func _run_air_test() -> void:
	if not is_instance_valid(world.atmo):
		print("[air] RESULT: FAILED — no atmosphere")
		return
	# The camera stands at the top of the world in all of this, so overhead is
	# the sub-solar point when the sun is up there too.
	var sun := Vector3.UP
	var by_alt: Array = []
	var ground := 0.0
	var space := 0.0
	for alt in [0.0, 3000.0, 11000.0, 30000.0, 60000.0, 140000.0]:
		var a: float = _air_alpha(float(alt), Vector3.UP, sun)
		by_alt.append("%.0fkm:%.2f" % [float(alt) * 0.001, a])
		if alt == 0.0:
			ground = a
		elif alt == 60000.0:
			space = a
	print("[air] looking straight up, the sky is: %s" % [
		", ".join(PackedStringArray(by_alt))])
	# There is more air toward the horizon than overhead, which is why the sky
	# pales that way. Measured high up rather than on the ground: down here both
	# directions are saturated -- a clear day really is opaque blue whichever way
	# you look -- and the difference only shows once the column stops filling.
	var zenith: float = _air_alpha(25000.0, Vector3.UP, sun)
	var level: float = _air_alpha(25000.0,
		Vector3(1.0, 0.02, 0.0).normalized(), sun)
	print("[air] at 25 km: %.2f overhead, %.2f toward the horizon" % [
		zenith, level])
	# The night side has to be clear, or the planet has no terminator and the
	# stars never come out.
	var night: float = _air_alpha(0.0, Vector3.UP, -Vector3.UP)
	# ...and the limb from orbit, which is the rim glow. A ray from 400 km whose
	# closest approach grazes ten kilometres over the ground: that is the bright
	# line round the edge of the planet.
	var graze: float = asin(clampf((Sim.PLANET_R + 10000.0)
		/ (Sim.PLANET_R + 400000.0), -1.0, 1.0))
	var limb: float = _air_alpha(400000.0,
		(-Vector3.UP * cos(graze) + Vector3.RIGHT * sin(graze)).normalized(), sun)
	print("[air] on the night side: %.3f; the limb seen from 400 km: %.2f" % [
		night, limb])
	# ...and what is behind the shell.
	#
	# A dim constant, and deliberately not a function of height any more: the
	# shell is the only thing that models the air now. This used to fade the
	# gradient out with altitude as well, which was a second ramp with its own
	# scale height fighting the shell's -- and a third lived in the sky shader.
	# Three models of one atmosphere is how a climb ends up with steps in it.
	# What matters here is only that the backdrop is dark enough to read as
	# space once the shell has thinned away over it.
	world.weather.thin_air(world._env, 0.0, world._psm)
	var behind: Color = world._psm.get_shader_parameter("top_colour")
	var sky_hi: float = behind.r + behind.g + behind.b
	print("[air] behind the shell the sky sits at %.3f whatever the height" % [
		sky_hi])
	print("[air] the shell stands %.0f km up and thins by e every %.0f km" % [
		Atmosphere.HEIGHT * 0.001,
		Atmosphere.HEIGHT / Atmosphere.RHO_EXP * 0.001])
	var ok: bool = ground > 0.55 and space < 0.10 and level > zenith \
		and night < 0.02 and limb > 0.08 and sky_hi < 0.25
	print("[air] RESULT: %s" % ("ok" if ok else "FAILED"))

## The shell's whole-column opacity, as `a_full` in the shader.
func _air_alpha(alt: float, dir: Vector3, sun: Vector3) -> float:
	var pr: float = Sim.PLANET_R
	var ar: float = pr + Atmosphere.HEIGHT
	var oc: Vector3 = Vector3.UP * (pr + alt)
	var b: float = oc.dot(dir)
	var disc: float = b * b - (oc.dot(oc) - ar * ar)
	if disc <= 0.0:
		return 0.0
	var sq: float = sqrt(disc)
	var t0: float = maxf(-b - sq, 0.0)
	var t1: float = -b + sq
	var discp: float = b * b - (oc.dot(oc) - pr * pr)
	if discp > 0.0:
		var tp: float = -b - sqrt(discp)
		if tp > 0.0:
			t1 = minf(t1, tp)
	var path: float = maxf(t1 - t0, 0.0)
	if path <= 0.0:
		return 0.0
	var max_chord: float = 2.0 * sqrt(ar * ar - pr * pr)
	var shell: float = ar - pr
	var cam_h: float = oc.length() - pr
	var inside: float = clampf(1.0 - cam_h / shell, 0.0, 1.0)
	var depth_up: float = clampf(path / maxf(shell - cam_h, 1.0), 0.0, 1.0) * inside
	var by_chord: float = clampf(path / max_chord, 0.0, 1.0)
	var by_up: float = depth_up * 0.8
	var depth_n: float = lerpf(by_chord, by_up,
		smoothstep(-0.18, 0.18, by_up - by_chord))
	var mid: Vector3 = oc + dir * clampf(-b, t0, t1)
	var alt01: float = clampf((mid.length() - pr) / shell, 0.0, 1.0)
	var air_at: float = exp(-alt01 * Atmosphere.RHO_EXP)
	var gate: float = clampf(mid.normalized().dot(sun) * 1.1 + 0.28, 0.0, 1.0)
	return clampf(depth_n * air_at * 1.5, 0.0, 0.92) * smoothstep(0.0, 0.25, gate)
#endregion


#region --suntest
var _sun_test := false

func tick_sun() -> bool:
	if _sun_test:
		_sun_test = false
		_run_sun_test()
		world.get_tree().quit()
		return true
	return false

## The sun, the seasons, and the climate bands that come out of them.
##
## The light used to be a fixed declination at a fixed latitude -- one
## afternoon, the same everywhere. The countries are spread from the tropics to
## the far north now, so where you are has to decide where the sun is, and the
## planet has to be tilted for there to be seasons at all.
func _run_sun_test() -> void:
	var lat: float = world.weather.latitude()
	print("[sun] the chart is at %.1f deg; the axis is tipped %.2f deg" % [
		rad_to_deg(lat), rad_to_deg(Weather.OBLIQUITY)])
	# Noon, through the year. The swing between midsummer and midwinter is twice
	# the obliquity wherever you stand, which is what having a tilt means.
	var noon: Array = []
	var hi := -9.0
	var lo := 9.0
	for d in 8:
		world.weather.day_of_year = float(d) * Weather.YEAR_DAYS / 8.0
		var e: float = world.weather.solar_angles(12.0).x
		noon.append("%.0f" % rad_to_deg(e))
		hi = maxf(hi, e)
		lo = minf(lo, e)
	print("[sun] the noon sun through the year, in degrees: %s" % [
		", ".join(PackedStringArray(noon))])
	print("[sun] midsummer to midwinter is %.1f deg; twice the tilt is %.1f" % [
		rad_to_deg(hi - lo), rad_to_deg(2.0 * Weather.OBLIQUITY)])
	# How long the day is at each solstice. Which of the two is summer depends
	# on the hemisphere -- the chart can be either -- so both are reported and
	# what is checked is that they differ, because a planet whose days are the
	# same length in June and December has no tilt.
	world.weather.day_of_year = Weather.YEAR_DAYS * 0.25
	var june: float = _daylight_hours()
	world.weather.day_of_year = Weather.YEAR_DAYS * 0.75
	var december: float = _daylight_hours()
	var here_day: float = maxf(june, december)
	print("[sun] the day is %.1f hours at one solstice and %.1f at the other" % [
		june, december])
	# The snow line, at each solstice. This is what the season is *for*: the
	# biome rule takes a warmth term off the sun's declination, so midwinter
	# pushes snow down the hills and midsummer takes it back up. Three separate
	# copies of that rule read it -- the terrain shader, the extension's map
	# rasteriser and `Sim`'s own -- from one pushed value.
	var lines: Array = []
	var snow_hi := 0.0
	var snow_lo := 0.0
	for phase in [0.25, 0.75]:
		world.weather.day_of_year = Weather.YEAR_DAYS * float(phase)
		Sim.season = world.weather.season()
		var line := -1.0
		# Up a column over the middle of the chart until the ground would be
		# snow. Asked of `Sim`, which is the copy the game stands on.
		for m in 60:
			var h: float = float(m) * 60.0
			var w: PackedFloat32Array = Sim.biomes.weights(0.0, 0.0, h, 1.0)
			if w.size() > 0 and w[0] > 0.5:
				line = h
				break
		lines.append("%.0f m" % line if line >= 0.0 else "none below 3600 m")
		if phase == 0.25:
			snow_hi = line
		else:
			snow_lo = line
	print("[sun] the snow line at the two solstices: %s" % [
		" and ".join(PackedStringArray(lines))])
	# The two copies of the climate scale. One number about the planet's tilt,
	# and it has been two copies of it before.
	var gd: float = Sim.CLIMATE_SQUEEZE
	var rs: float = Sim.native.climate_squeeze()
	var want: float = 1.0 / sin(PI * 0.5 - Weather.OBLIQUITY)
	print("[sun] the climate scale is %.4f here and %.4f in the extension; the tilt says %.4f" % [
		gd, rs, want])
	world.weather.day_of_year = 0.0
	Sim.season = world.weather.season()
	var ok: bool = absf((hi - lo) - 2.0 * Weather.OBLIQUITY) < deg_to_rad(0.6) \
		and absf(gd - rs) < 0.001 and absf(gd - want) < 0.002 \
		and here_day > 0.0 and absf(june - december) > 1.0 \
		and absf(snow_hi - snow_lo) > 1.0
	print("[sun] RESULT: %s" % ("ok" if ok else "FAILED"))

## How many hours the sun is above the horizon for, on the current day.
func _daylight_hours() -> float:
	var lit := 0.0
	for i in 240:
		if world.weather.solar_angles(float(i) * 24.0 / 240.0).x > 0.0:
			lit += 24.0 / 240.0
	return lit
#endregion


#region --layertest
var _layer_test := false

func tick_layer() -> bool:
	if _layer_test:
		_layer_test = false
		await _run_layer_test()
		world.get_tree().quit()
		return true
	return false

## What is actually on the screen, layer by layer.
##
## Run this one with a window -- it reads the rendered frame, and a headless run
## has no frame to read:
##
##     Godot --path . -- --layertest
##
## Everything that could put a white wash over the view is measured and then
## taken away one at a time: the cloud shell, the atmosphere, the depth fog and
## the sky itself. Whichever removal makes the picture stop being white is the
## one doing it.
##
## This exists because the field measurements all say the sky is clear -- 93 per
## cent of it open in clear weather, the air transparent above fifty kilometres
## -- and the screen says otherwise. One of those is wrong about the *frame*
## rather than about the field, and no amount of reading the shaders settles
## which.
func _run_layer_test() -> void:
	if DisplayServer.get_name() == "headless":
		print("[layer] RESULT: FAILED — needs a window; run without --headless")
		return
	world._start("f16", "free")
	await world.get_tree().process_frame
	await world.get_tree().physics_frame
	# Level, a few thousand feet up, looking at the horizon: the view the
	# reports are about.
	if is_instance_valid(world.player):
		world.player.global_transform = Transform3D(Basis(),
			Vector3(0.0, world._apron_y(0.0, 0.0) + 3000.0, 0.0))
	for _i in 8:
		await world.get_tree().process_frame
	var rows: Array = []
	var costs: Array = []
	var base_lum := 0.0
	var base_sat := 0.0
	var worst_drop := 0.0
	var culprit := "nothing"
	# "sky only" and "atmosphere only" are the two halves of the question the
	# last run left open: the sky gradient is what was washing the view out, and
	# the shell is meant to be what replaces it.
	# Where the sun is relative to the view, because a sun disc drawn at six
	# times white and then bloomed will wash a frame out on its own -- and that
	# would look exactly like the flat, desaturated white being reported.
	var camf: Camera3D = world.get_viewport().get_camera_3d()
	if camf != null and is_instance_valid(world._sun):
		var fwd: Vector3 = -camf.global_transform.basis.z
		var tosun: Vector3 = world._sun.global_transform.basis.z
		print("[layer] the sun is %.0f deg up and %.0f deg off the view" % [
			rad_to_deg(asin(clampf(tosun.dot(Vector3.UP), -1.0, 1.0))),
			rad_to_deg(acos(clampf(fwd.dot(tosun), -1.0, 1.0)))])
	for step in ["everything", "no cloud", "no atmosphere", "no fog", "no sky",
			"sky only", "no glow", "no tonemap"]:
		_layer_set(step)
		for _j in 4:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = world.get_viewport().get_texture().get_image()
		# What the layer costs, as well as what it looks like. Timed over forty
		# frames with it off against forty with everything on: the difference is
		# what that layer is worth in milliseconds.
		var t_sum := 0.0
		for _t in 40:
			await world.get_tree().process_frame
			t_sum += world.get_process_delta_time()
		var ms: float = t_sum / 40.0 * 1000.0
		costs.append("%s %.1f ms" % [step, ms])
		var acc := Color(0.0, 0.0, 0.0)
		var n := 0
		# The top half of the frame, which is sky rather than ground.
		for y in range(0, int(img.get_height() / 2.0), 8):
			for x in range(0, img.get_width(), 8):
				var c: Color = img.get_pixel(x, y)
				acc += c
				n += 1
		var inv: float = 1.0 / maxf(float(n), 1.0)
		acc = Color(acc.r * inv, acc.g * inv, acc.b * inv)
		var lum: float = (acc.r + acc.g + acc.b) / 3.0
		# Whether it is white or blue, which brightness alone cannot say -- and
		# which is the whole of the complaint. A grey sky has no saturation; a
		# real one has a third of it or more.
		var mx: float = maxf(acc.r, maxf(acc.g, acc.b))
		var mn: float = minf(acc.r, minf(acc.g, acc.b))
		var sat: float = (mx - mn) / maxf(mx, 1e-4)
		rows.append("%s %.2f lum/%.2f sat rgb(%.2f %.2f %.2f)" % [
			step, lum, sat, acc.r, acc.g, acc.b])
		if step == "everything":
			base_lum = lum
			base_sat = sat
		elif base_lum - lum > worst_drop:
			worst_drop = base_lum - lum
			culprit = step
		_layer_set("everything")
	# A picture of the frame, in characters.
	#
	# Three rounds of bisection produced one number per layer and no answer:
	# every layer said "not me" and the frame stayed white. A single mean cannot
	# tell a white sky from white ground from a wash over everything, and that
	# distinction is the whole question. This is small enough to read in a log
	# and says immediately where the horizon is and what is bright.
	_layer_set("everything")
	for _k in 4:
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var pic: Image = world.get_viewport().get_texture().get_image()
	const RAMP := " .:-=+*#%@"
	print("[layer] the frame, darkest ' ' to brightest '@':")
	for row in 14:
		var line := ""
		for col in 40:
			var px: int = int(float(col) / 40.0 * float(pic.get_width()))
			var py: int = int(float(row) / 14.0 * float(pic.get_height()))
			var c: Color = pic.get_pixel(mini(px, pic.get_width() - 1),
				mini(py, pic.get_height() - 1))
			var v: float = clampf((c.r + c.g + c.b) / 3.0, 0.0, 0.999)
			line += RAMP[int(v * 10.0)]
		print("[layer]   |%s|" % line)
	print("[layer] what each layer costs a frame: %s" % [
		", ".join(PackedStringArray(costs))])
	print("[layer] mean brightness of the upper half of the frame: %s" % [
		", ".join(PackedStringArray(rows))])
	print("[layer] taking away '%s' darkens it most, by %.3f" % [
		culprit, worst_drop])
	# A sky is blue, which is a statement about saturation and not about
	# brightness. The wash this was built to find measured 0.82 bright and 0.01
	# saturated; the atmosphere shell on its own measured 0.51 and 0.60.
	# Does the light follow the sun?
	#
	# The ground's brightness through a day, against the sun's own elevation.
	# If the two do not move together then whatever is lighting the world is not
	# the sun, which is what "lighting not based on sun position" means.
	var day_rows: Array = []
	var lit_hi := 0.0
	var lit_lo := 9.0
	var was_hour: float = world.weather.time_of_day
	for hour in [0.0, 4.0, 8.0, 12.0, 16.0, 20.0]:
		world.weather.time_of_day = float(hour)
		for _q in 3:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var gi: Image = world.get_viewport().get_texture().get_image()
		# The lower half: ground, which is what the sun lights.
		var g := 0.0
		var gn := 0
		for y in range(int(gi.get_height() / 2.0), gi.get_height(), 8):
			for x in range(0, gi.get_width(), 8):
				var c: Color = gi.get_pixel(x, y)
				g += (c.r + c.g + c.b) / 3.0
				gn += 1
		g /= maxf(float(gn), 1.0)
		var el: float = rad_to_deg(world.weather.sun_elevation())
		day_rows.append("%02.0fh sun %+.0f deg ground %.2f" % [hour, el, g])
		lit_hi = maxf(lit_hi, g)
		lit_lo = minf(lit_lo, g)
	world.weather.time_of_day = was_hour
	print("[layer] through the day: %s" % [
		", ".join(PackedStringArray(day_rows))])
	print("[layer] the ground runs %.2f to %.2f over a day" % [lit_lo, lit_hi])
	# What the sky shader is actually being told to draw. Reading the uniform
	# rather than the source, because the source has twice now said one thing
	# while the frame said another.
	if world._psm != null:
		print("[layer] the sky's own colours: top %s horizon %s" % [
			str(world._psm.get_shader_parameter("top_colour")),
			str(world._psm.get_shader_parameter("horizon_colour"))])
	# ...and climbing out of the air, which is the ASAT's complaint: the sky has
	# to stop being sky and start being space.
	var climb_rows: Array = []
	var high_sat := 0.0
	var high_lum := 1.0
	# Finer steps through the transition, because a jump is what is being
	# reported and a four point sweep cannot show one.
	for alt in [3000.0, 15000.0, 30000.0, 45000.0, 60000.0, 80000.0,
			100000.0, 140000.0]:
		if is_instance_valid(world.player):
			world.player.global_transform = Transform3D(Basis(),
				Vector3(0.0, float(alt), 0.0))
		for _q2 in 4:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var ci: Image = world.get_viewport().get_texture().get_image()
		var a2 := Color(0.0, 0.0, 0.0)
		var cn := 0
		for y in range(0, int(ci.get_height() / 3.0), 8):
			for x in range(0, ci.get_width(), 8):
				a2 += ci.get_pixel(x, y)
				cn += 1
		var iv: float = 1.0 / maxf(float(cn), 1.0)
		a2 = Color(a2.r * iv, a2.g * iv, a2.b * iv)
		var l2: float = (a2.r + a2.g + a2.b) / 3.0
		var mx2: float = maxf(a2.r, maxf(a2.g, a2.b))
		var mn2: float = minf(a2.r, minf(a2.g, a2.b))
		var s2: float = (mx2 - mn2) / maxf(mx2, 1e-4)
		# Stars, counted rather than averaged: they are single bright pixels on
		# a dark field and a mean over every eighth pixel steps straight past
		# them. Anything well above the local sky brightness in the top third.
		var stars := 0
		var brightest := 0.0
		for y in range(0, int(ci.get_height() / 3.0), 2):
			for x in range(0, ci.get_width(), 2):
				var sc: Color = ci.get_pixel(x, y)
				var sv: float = (sc.r + sc.g + sc.b) / 3.0
				brightest = maxf(brightest, sv)
				# An absolute threshold, not one relative to the sky: a star is
				# a bright point, and "brighter than the average" counts the
				# top of a gradient as well.
				if sv > 0.30:
					stars += 1
		climb_rows.append("%.0fkm %.2f lum/%.2f sat/%d pts/max %.2f" % [
			alt * 0.001, l2, s2, stars, brightest])
		if alt >= 140000.0:
			# A picture from up there too. At the ground it took one look to see
			# that the top half really was sky; from orbit it might be the
			# planet filling the frame, which would mean nothing is wrong at all.
			print("[layer] the frame at %.0f km:" % (alt * 0.001))
			for row in 10:
				var ln := ""
				for col in 40:
					var qx: int = int(float(col) / 40.0 * float(ci.get_width()))
					var qy: int = int(float(row) / 10.0 * float(ci.get_height()))
					var cc: Color = ci.get_pixel(mini(qx, ci.get_width() - 1),
						mini(qy, ci.get_height() - 1))
					var vv: float = clampf((cc.r + cc.g + cc.b) / 3.0, 0.0, 0.999)
					ln += " .:-=+*#%@"[int(vv * 10.0)]
				print("[layer]   |%s|" % ln)
			high_lum = l2
			high_sat = s2
	# The same bisection, up where the problem is. Every reading so far has been
	# taken at three thousand feet, and the frame at a hundred and forty
	# kilometres is a solid wall of white -- which no layer measured down here
	# accounts for.
	if is_instance_valid(world.player):
		world.player.global_transform = Transform3D(Basis(),
			Vector3(0.0, 140000.0, 0.0))
	var high_rows: Array = []
	for step2 in ["everything", "no cloud", "no atmosphere", "no fog", "no sky",
			"no glow", "no tonemap"]:
		_layer_set(step2)
		for _q3 in 4:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var hi2: Image = world.get_viewport().get_texture().get_image()
		var ha := Color(0.0, 0.0, 0.0)
		var hn := 0
		for y in range(0, int(hi2.get_height() / 2.0), 8):
			for x in range(0, hi2.get_width(), 8):
				ha += hi2.get_pixel(x, y)
				hn += 1
		var hv: float = 1.0 / maxf(float(hn), 1.0)
		ha = Color(ha.r * hv, ha.g * hv, ha.b * hv)
		high_rows.append("%s %.2f" % [step2, (ha.r + ha.g + ha.b) / 3.0])
		_layer_set("everything")
	print("[layer] at 140 km, layer by layer: %s" % [
		", ".join(PackedStringArray(high_rows))])
	print("[layer] climbing out: %s" % [
		", ".join(PackedStringArray(climb_rows))])
	print("[layer] at 140 km the sky is %.2f bright and %.2f saturated — space is both near 0" % [
		high_lum, high_sat])
	print("[layer] RESULT: %s" % ("ok" if base_lum < 0.72 and base_sat > 0.25
		and lit_hi - lit_lo > 0.10 and high_lum < 0.15
		else "FAILED — sky %.2f bright/%.2f sat, ground moves %.2f over a day, "
			% [base_lum, base_sat, lit_hi - lit_lo]
			+ "140 km reads %.2f; '%s' washes it most" % [high_lum, culprit]))

## Turn one contributor off, or all of them back on.
func _layer_set(which: String) -> void:
	if is_instance_valid(world.clouds):
		world.clouds.visible = which != "no cloud"
	if is_instance_valid(world.atmo):
		world.atmo.visible = which != "no atmosphere" and which != "sky only"
	if world._env != null:
		world._env.glow_enabled = which != "no glow"
		world._env.tonemap_mode = Environment.TONE_MAPPER_LINEAR \
			if which == "no tonemap" else Environment.TONE_MAPPER_ACES
		world._env.fog_enabled = which != "no fog"
		world._env.background_mode = Environment.BG_COLOR if which == "no sky" \
			else Environment.BG_SKY
		world._env.background_color = Color(0.0, 0.0, 0.0)
#endregion


#region --mapshot
var _map_shot := false
var map_lit := 0
var map_total := 1
var map_sun_off := 0.0
var map_day := 0.0
var map_night := 0.0

func tick_map_shot() -> bool:
	if _map_shot:
		_map_shot = false
		await _run_map_shot()
		world.get_tree().quit()
		return true
	return false

## What the map actually looks like.
##
## Needs a window, like `--layertest`. The planet is the only map now -- the
## flat chart is gone except on `--flat` -- so if it draws nothing the game has
## no map at all, and nothing in the headless tests would say so: they check
## the projection and the sheet, both of which can be perfectly correct behind a
## view that never appears.
func _run_map_shot() -> void:
	if DisplayServer.get_name() == "headless":
		print("[mapshot] RESULT: FAILED — needs a window; run without --headless")
		return
	world._start("f16", "free")
	await world.get_tree().process_frame
	await world.get_tree().physics_frame
	for _i in 10:
		await world.get_tree().process_frame
	# Does the map light the planet the way the world lights the ground?
	#
	# The map works its own sun out from the solar angles; the world points a
	# DirectionalLight. Two derivations of one fact, which in this project has
	# meant a disagreement more often than not.
	# The map's sun is in the planet's frame; the world's light is in the local
	# frame at the chart's origin. Comparing them raw says nothing -- they are
	# the same direction written two ways, and comparing the two literals is
	# what let a 42 degree error pass as "0.0 deg apart". The world's is put
	# into the planet's frame first, the same way the map does it.
	var lit_map: Vector3 = world.map.globe_view.call("_globe_light", Basis())
	var w0: Vector3 = world._sun.global_transform.basis.z \
		if is_instance_valid(world._sun) else Vector3.UP
	var lit_world: Vector3 = (Sim.chart_origin * w0.y + Sim.chart_east * w0.x
		+ (-Sim.chart_south) * (-w0.z)).normalized()
	var off: float = rad_to_deg(acos(clampf(
		lit_map.normalized().dot(lit_world.normalized()), -1.0, 1.0)))
	print("[mapshot] the map's sun is %s, the world's is %s — %.1f deg apart" % [
		str(lit_map.snapped(Vector3.ONE * 0.01)),
		str(lit_world.snapped(Vector3.ONE * 0.01)), off])
	map_sun_off = off
	# What the mesh itself is shaded with, before anything draws it. If these
	# are all one value the globe has no terminator no matter what the frame
	# looks like.
	var mesh_c: Array = Sim.native.globe_mesh(64, 72, Vector2(960.0, 540.0),
		450.0, Basis(), lit_map)
	var cols: PackedColorArray = mesh_c[2]
	var cmin := 9.0
	var cmax := -9.0
	for c in cols:
		cmin = minf(cmin, (c as Color).r)
		cmax = maxf(cmax, (c as Color).r)
	print("[mapshot] the globe mesh is shaded from %.2f to %.2f over %d corners" % [
		cmin, cmax, cols.size()])
	# ...and is there a sheet to paint it with? `_globe_body` returns without
	# drawing anything when there is not, and then the only things on the map
	# are the graticule and the marks -- which is a picture with no planet in it
	# and no terminator either, however well the mesh is shaded.
	var sheet_tex: Variant = world.map.call("_planet_sheet")
	print("[mapshot] the planet sheet is %s" % [
		"missing" if sheet_tex == null else "%dx%d" % [
			(sheet_tex as Texture2D).get_width(),
			(sheet_tex as Texture2D).get_height()]])
	world.map.toggle_globe()
	# Noon against midnight. If the globe is shaded by the sun at all, the disc
	# must be plainly darker at one than the other -- and if it is not, the
	# vertex colours are not reaching the draw, whatever the mesh says they are.
	var was_hour: float = world.weather.time_of_day
	var disc: Array = []
	for hour in [12.0, 0.0]:
		world.weather.time_of_day = float(hour)
		world.map.globe_zoom = 1.0
		for _h in 20:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var di: Image = world.get_viewport().get_texture().get_image()
		var rr2: float = minf(float(di.get_width()), float(di.get_height())) * 0.42
		var sm := 0.0
		var sn := 0
		for y in range(0, di.get_height(), 3):
			for x in range(0, di.get_width(), 3):
				var ddx: float = float(x) - float(di.get_width()) * 0.5
				var ddy: float = float(y) - float(di.get_height()) * 0.5
				if ddx * ddx + ddy * ddy > rr2 * rr2 * 0.85:
					continue
				var pc: Color = di.get_pixel(x, y)
				sm += (pc.r + pc.g + pc.b) / 3.0
				sn += 1
		disc.append(sm / maxf(float(sn), 1.0))
	world.weather.time_of_day = was_hour
	print("[mapshot] the whole disc reads %.3f at noon and %.3f at midnight" % [
		disc[0], disc[1]])
	for zoom_at in [1.0, 12.0]:
		world.map.globe_zoom = float(zoom_at)
		for _j in 30:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = world.get_viewport().get_texture().get_image()
		var acc := Color(0.0, 0.0, 0.0)
		var n := 0
		var lit := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var c: Color = img.get_pixel(x, y)
				acc += c
				n += 1
				if (c.r + c.g + c.b) / 3.0 > 0.10:
					lit += 1
		var iv: float = 1.0 / maxf(float(n), 1.0)
		acc = Color(acc.r * iv, acc.g * iv, acc.b * iv)
		print("[mapshot] at x%.0f: mean rgb(%.2f %.2f %.2f), %d%% of it lit" % [
			float(zoom_at), acc.r, acc.g, acc.b,
			int(round(100.0 * float(lit) / maxf(float(n), 1.0)))])
		print("[mapshot] the map at x%.0f:" % float(zoom_at))
		for row in 16:
			var line := ""
			for col in 52:
				var px: int = int(float(col) / 52.0 * float(img.get_width()))
				var py: int = int(float(row) / 16.0 * float(img.get_height()))
				var cc: Color = img.get_pixel(mini(px, img.get_width() - 1),
					mini(py, img.get_height() - 1))
				var vv: float = clampf((cc.r + cc.g + cc.b) / 3.0, 0.0, 0.999)
				line += " .:-=+*#%@"[int(vv * 10.0)]
			print("[mapshot]   |%s|" % line)
		map_lit = lit
		map_total = n
		# Is there a terminator on it?
		#
		# The globe is shaded by the real sun, so the half facing it must be
		# plainly brighter than the half that is not. Both ways of getting this
		# wrong have happened: a 0.16 floor made the night side a hole, and
		# lifting it to 0.45 made the whole planet read as lit. What is measured
		# is the contrast across the terminator, which fails on either.
		# The captured image is in physical pixels; the map lays the globe out in
		# the viewport's logical ones, and on a Retina display those differ by a
		# factor of two. Measured in the wrong units the sampled disc is half the
		# size of the drawn one, so every sample lands near its middle -- where
		# the two hemispheres cannot be told apart, which is exactly the flat
		# reading this kept producing.
		var vpr: Vector2 = world.map.get_viewport_rect().size
		var scale_px: float = float(img.get_width()) / maxf(vpr.x, 1.0)
		print("[mapshot] viewport %s, captured %dx%d, scale %.2f" % [
			str(vpr), img.get_width(), img.get_height(), scale_px])
		var rad2: float = minf(vpr.x, vpr.y) * 0.42 * float(zoom_at) * scale_px
		var bas: Basis = world.map.globe_view.call("_globe_basis")
		var sunv: Vector3 = world.map.globe_view.call("_globe_light", bas)
		var day_sum := 0.0
		var day_n := 0
		var night_sum := 0.0
		var night_n := 0
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				var dx: float = (float(x) - float(img.get_width()) * 0.5) / rad2
				var dy: float = (float(y) - float(img.get_height()) * 0.5) / rad2
				var rr: float = dx * dx + dy * dy
				if rr > 0.92:
					continue
				# The point on the near face of the ball, in the same view
				# space the mesh and the light are in.
				var nrm := Vector3(dx, -dy, sqrt(maxf(1.0 - rr, 0.0)))
				var c2: Color = img.get_pixel(x, y)
				var v2: float = (c2.r + c2.g + c2.b) / 3.0
				if nrm.dot(sunv) > 0.25:
					day_sum += v2
					day_n += 1
				elif nrm.dot(sunv) < -0.25:
					night_sum += v2
					night_n += 1
		var day_m: float = day_sum / maxf(float(day_n), 1.0)
		var night_m: float = night_sum / maxf(float(night_n), 1.0)
		print("[mapshot] at x%.0f the sunlit side reads %.3f over %d px and the dark side %.3f over %d px; the sun in view is %s" % [
			float(zoom_at), day_m, day_n, night_m, night_n,
			str(sunv.snapped(Vector3.ONE * 0.01))])
		# Only where the whole ball is on screen: zoomed in, every sample is
		# near the middle of the disc and the two hemispheres cannot be told
		# apart by screen position at all.
		if zoom_at < 2.0:
			map_day = day_m
			map_night = night_m
	print("[mapshot] RESULT: %s" % ("ok" if map_lit * 5 > map_total
		and map_sun_off < 2.0
		# A terminator you can see, and a night side that is not a hole.
		and map_day > map_night * 1.6 and map_night > 0.02
		else "FAILED — %d%% of the map is lit and its sun is %.1f deg off the "
			% [int(round(100.0 * float(map_lit) / maxf(float(map_total), 1.0))),
			map_sun_off] + "world's"))
#endregion


#region --costtest
var _cost_test := false

func tick_cost() -> bool:
	if _cost_test:
		_cost_test = false
		await _run_cost_test()
		world.get_tree().quit()
		return true
	return false

## The globe mode of the tactical map: does it put the ground where the ground
## is, and does it hide what is round the back?
##
## A globe is easy to draw and easy to draw wrongly, and both mistakes look
## plausible in a screenshot. What is checked here is that the theatre lands
## under the middle of the screen when you are looking at it, that a point on
## the far side of the planet is reported as facing away rather than drawn
## folded over the near side, that turning the globe by half a turn swaps the
## two, and that the projection is the same size as the planet it claims to be.
## Does the planet map actually resolve more as you zoom in?
##
## The globe reads one sheet of the whole planet. Zoomed right in that is a few
## texels stretched over the screen, so "more detail" has to mean baking the
## cap being looked at. Two things have to hold: the window has to shrink as
## the zoom grows, and what is baked into it has to be the same world the base
## sheet shows -- a finer picture of the same place, not a different one.
## What each feature of the world costs a frame.
##
## Needs a window. `--layertest` does this for the sky and accounts for three
## milliseconds of sixteen; this does it for everything that is drawn, which is
## where the rest of the frame goes. Each subject is hidden, the frame is timed,
## and the difference is what it was worth -- the same method, pointed at the
## scene instead of the shaders.
##
## Hiding a node is not the same as deleting it: the culling and the scene walk
## still happen. What this measures is the cost of *drawing* a thing, which is
## the part a level of detail or a draw distance can take away.
func _run_cost_test() -> void:
	if DisplayServer.get_name() == "headless":
		print("[cost] RESULT: FAILED — needs a window; run without --headless")
		return
	# Whatever is already running, if something is.
	#
	# This always started its own free flight two kilometres up, so the one
	# situation it could measure was the one situation. On foot the frame is a
	# hundred milliseconds against twelve in the air, and there was no way to
	# point this at it. With a `--preset` the mission it names is left alone.
	if not world.running:
		world._start("f16", "free")
		await world.get_tree().process_frame
		await world.get_tree().physics_frame
		if is_instance_valid(world.player):
			world.player.global_transform = Transform3D(Basis(),
				Vector3(0.0, world._apron_y(0.0, 0.0) + 2000.0, 0.0))
	for _i in 40:
		await world.get_tree().process_frame
	# Everything worth asking about, by name.
	var subjects: Array = []
	for nm in ["Scenery", "Terrain", "Planet", "Obstacles", "Clouds",
			"Atmosphere", "Carrier"]:
		var n := world.get_node_or_null(NodePath(nm))
		if n != null and n is Node3D:
			subjects.append([nm, n])
	for b in world.bases:
		if is_instance_valid(b):
			subjects.append([String(b.name), b])
	# ...and what is inside the scenery, which is where four fifths of the
	# triangles are.
	#
	# By size, not one by one. The scenery has eighteen hundred children and
	# almost every one has a name and a mesh of its own, so neither listing them
	# nor grouping them by name gets anywhere -- timing each in turn is a run
	# measured in hours. They are ranked by how many triangles they actually
	# submit; the ten biggest are timed on their own and the whole tail is timed
	# together, which is the granularity a draw distance would work at anyway.
	if is_instance_valid(world.scenery):
		var ranked: Array = []
		for c in world.scenery.get_children():
			var tris := 0
			var mesh: Mesh = null
			var mult := 1
			if c is MeshInstance3D:
				mesh = (c as MeshInstance3D).mesh
			elif c is MultiMeshInstance3D:
				var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
				if mm != null:
					mesh = mm.mesh
					mult = maxi(mm.instance_count, 1)
			if mesh == null:
				continue
			for si in mesh.get_surface_count():
				if mesh is ArrayMesh:
					tris += int((mesh as ArrayMesh).surface_get_array_len(si) / 3.0)
			ranked.append([String(c.name), c, tris * mult])
		ranked.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
		var tail: Array = []
		for k in ranked.size():
			var rk: Array = ranked[k]
			if k < 10:
				subjects.append(["scenery: %s (%.2f M tri)"
					% [String(rk[0]), float(rk[2]) / 1e6], rk[1]])
			else:
				tail.append(rk[1])
		if not tail.is_empty():
			subjects.append(["scenery: the other %d" % tail.size(), tail])
	print("[cost] %d subjects to time" % subjects.size())
	# Everything at once, before anything individually.
	#
	# If the frame with the whole world hidden is still most of the frame with
	# it shown, then no amount of hiding one thing at a time will ever add up:
	# the cost is not in what is being drawn. That is worth knowing before
	# twenty minutes are spent apportioning it.
	var everything: Array = []
	for c in world.get_children():
		if c is Node3D and (c as Node3D).visible:
			everything.append(c)
	var base_ms: float = await _time_frames()
	var base_calls: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("[cost] baseline %.2f ms, %d draw calls, %.2f M triangles, %.0f MB video, %d objects" % [
		base_ms, base_calls, float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)) / 1e6,
		float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT)])
	# What is in the floor. The frame with nothing drawn is most of the frame,
	# and these are the engine-side counters that could account for it.
	print("[cost] engine: process %.2f ms, physics %.2f ms, %d nodes, %d bodies, %d pairs, %d islands" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	# Checked before it is typed: the list was gathered a second ago and the
	# world frees things constantly -- a spent round, an effect, a wreck -- and
	# assigning a freed instance to a typed variable is itself the error.
	for nd in everything:
		if is_instance_valid(nd):
			(nd as Node3D).visible = false
	var empty_ms: float = await _time_frames()
	var empty_tris: float = float(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	for nd in everything:
		if is_instance_valid(nd):
			(nd as Node3D).visible = true
	print("[cost] with the whole world hidden the frame is %.2f ms and draws %.2f M triangles" % [
		empty_ms, empty_tris / 1e6])
	print("[cost] so everything drawn is worth %.2f ms of the %.2f ms frame" % [
		base_ms - empty_ms, base_ms])
	var rows: Array = []
	for sub in subjects:
		var what: Variant = (sub as Array)[1]
		var nodes: Array = what if what is Array else [what]
		var shown: Array = []
		for nd in nodes:
			if is_instance_valid(nd) and (nd as Node3D).visible:
				shown.append(nd)
		if shown.is_empty():
			continue
		for nd in shown:
			(nd as Node3D).visible = false
		var ms: float = await _time_frames()
		var calls: int = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		for nd in shown:
			(nd as Node3D).visible = true
		# Against a baseline taken next to it, not one from the start of the
		# run: the machine drifts over a couple of minutes and a subject timed
		# last would otherwise carry all of that drift as its own cost.
		var near_base: float = await _time_frames()
		rows.append([String((sub as Array)[0]) + (" x%d" % shown.size()
			if shown.size() > 1 else ""), near_base - ms, base_calls - calls])
	# The sun's shadow map is not a node, and it is often most of a frame.
	if is_instance_valid(world._sun) and world._sun.shadow_enabled:
		world._sun.shadow_enabled = false
		var sms: float = await _time_frames()
		world._sun.shadow_enabled = true
		rows.append(["<shadow map>", base_ms - sms, 0])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var named := 0.0
	print("[cost] what each thing is worth, hidden one at a time:")
	for r in rows:
		var rr: Array = r
		if absf(float(rr[1])) < 0.05:
			continue
		named += maxf(float(rr[1]), 0.0)
		print("[cost]   %-26s %6.2f ms   %5d fewer draw calls" % [
			String(rr[0]), float(rr[1]), int(rr[2])])
	# Against what the world is worth, not against the whole frame.
	#
	# This used to be gated on the census accounting for half the *frame*, and
	# it cannot: half the frame is there with every object hidden, and the floor
	# census below shows that none of that half is anything the game switches on.
	# What this test can honestly ask is whether the things it named add up to
	# what the world costs, which is the number it exists to apportion.
	var drawn: float = maxf(base_ms - empty_ms, 0.01)
	print("[cost] named: %.2f ms of the %.2f the world is worth — %d%% of it, and %d%% of the whole frame" % [
		named, drawn, int(round(100.0 * named / drawn)),
		int(round(100.0 * named / maxf(base_ms, 0.01)))])
	await _floor_census(everything)
	print("[cost] RESULT: %s" % ("ok" if named * 2.0 > drawn
		else "FAILED — only %d%% of what the world costs is attributed"
			% int(round(100.0 * named / drawn))))

## What the frame costs with nothing in the world drawn at all.
##
## Half the frame was in here and there was no way to say what any of it was:
## the census above walks the tree, and none of this is in the tree. A sky is a
## shader over every background pixel and a radiance cubemap behind that; the
## glow is a pyramid of the whole screen; the shadow map is drawn whether or not
## anything casts into it; and multisampling multiplies every one of those by
## the samples. Each is switched off on its own against a baseline taken beside
## it, because the machine drifts over the couple of minutes this run takes.
##
## What it found is that none of them is it: see the note at the end.
func _floor_census(everything: Array) -> void:
	for nd in everything:
		if is_instance_valid(nd):
			(nd as Node3D).visible = false
	var vp := world.get_viewport()
	var floor_ms: float = await _time_frames()
	var rows: Array = []
	# Between two baselines, not against one.
	#
	# The numbers here are tenths of a millisecond and the machine drifts by
	# more than that over the couple of minutes this run takes; measured against
	# a single baseline from the start, four of six probes came back negative --
	# switching a thing off made the frame slower. Taken as the mean of a
	# baseline either side of the probe, the drift cancels instead of landing on
	# whichever probe ran last.
	var probe := func(what: String, before: Callable, after: Callable) -> void:
		var lo: float = await _time_frames()
		before.call()
		var got: float = await _time_frames()
		after.call()
		var hi: float = await _time_frames()
		rows.append([what, (lo + hi) * 0.5 - got])
	# The sky, which is a shader run over every pixel the world does not cover
	# -- and, being a realtime sky, six faces of a radiance cubemap and their
	# mips re-rendered behind it every frame. The background mode alone does not
	# stop that: the Sky resource is still attached and still processing, which
	# is why switching only the background off measured nothing.
	var was_bg: int = world._env.background_mode
	var was_sky: Sky = world._env.sky
	await probe.call("the sky",
		func() -> void:
			world._env.background_mode = Environment.BG_COLOR
			world._env.sky = null,
		func() -> void:
			world._env.sky = was_sky
			world._env.background_mode = was_bg as Environment.BGMode)
	if was_sky != null and was_sky.process_mode == Sky.PROCESS_MODE_REALTIME:
		# ...and how much of that is the cubemap rather than the pixels: the
		# radiance is what the sky costs when you are not looking at it.
		await probe.call("  its radiance, alone",
			func() -> void: was_sky.process_mode = Sky.PROCESS_MODE_QUALITY,
			func() -> void: was_sky.process_mode = Sky.PROCESS_MODE_REALTIME)
	# The instruments, which are not in the tree this walked and are a few
	# hundred canvas items redrawn over the whole screen.
	var layer: CanvasLayer = null
	if is_instance_valid(world.hud):
		layer = world.hud.get_parent() as CanvasLayer
	if layer != null:
		await probe.call("the UI",
			func() -> void: layer.visible = false,
			func() -> void: layer.visible = true)
	if world._env.glow_enabled:
		await probe.call("glow",
			func() -> void: world._env.glow_enabled = false,
			func() -> void: world._env.glow_enabled = true)
	if world._env.fog_enabled:
		await probe.call("fog",
			func() -> void: world._env.fog_enabled = false,
			func() -> void: world._env.fog_enabled = true)
	if is_instance_valid(world._sun) and world._sun.shadow_enabled:
		await probe.call("the shadow map",
			func() -> void: world._sun.shadow_enabled = false,
			func() -> void: world._sun.shadow_enabled = true)
	var was_msaa: int = vp.msaa_3d
	if was_msaa != Viewport.MSAA_DISABLED:
		await probe.call("multisampling",
			func() -> void: vp.msaa_3d = Viewport.MSAA_DISABLED,
			func() -> void: vp.msaa_3d = was_msaa as Viewport.MSAA)
	var was_ssaa: int = vp.screen_space_aa
	if was_ssaa != Viewport.SCREEN_SPACE_AA_DISABLED:
		await probe.call("screen space AA",
			func() -> void: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED,
			func() -> void: vp.screen_space_aa = was_ssaa as Viewport.ScreenSpaceAA)
	# Hidden is not gone.
	#
	# Everything above is switched off and none of it moves the floor, and the
	# world above is *hidden* rather than taken out -- so a hidden instance is
	# still an instance the renderer holds, still in its acceleration structure
	# and still visited by the cull, once for the camera and again for every
	# split of the directional light. With twelve thousand of them that is the
	# one thing left that could be in here, and taking the largest branch out of
	# the tree entirely is the way to ask.
	var biggest: Node3D = null
	var most := 0
	for c in world.get_children():
		if c is Node3D and c.get_child_count() > most:
			most = c.get_child_count()
			biggest = c as Node3D
	if biggest != null and most > 100:
		var at := biggest.get_index()
		await probe.call("%s out of the tree, not hidden (%d children)"
			% [String(biggest.name), most],
			func() -> void: world.remove_child(biggest),
			func() -> void:
				world.add_child(biggest)
				world.move_child(biggest, at))
	# The physics step, which is not drawn at all and is a fifth of the frame.
	# A hundred and twenty ticks a second over five thousand nodes is a real
	# cost whether or not anything is moving, and none of it is in the tree the
	# census above walks.
	var was_hz: int = Engine.physics_ticks_per_second
	await probe.call("physics, at 10 Hz not %d" % was_hz,
		func() -> void: Engine.physics_ticks_per_second = 10,
		func() -> void: Engine.physics_ticks_per_second = was_hz)
	# ...and everything the tree does per frame, which is the last thing left
	# if none of the above is it.
	await probe.call("the whole tree, paused",
		func() -> void: world.get_tree().paused = true,
		func() -> void: world.get_tree().paused = false)
	# And if it *is* it, which branch. Pausing tells you the tree is the frame;
	# it does not tell you whose script. Each branch is stopped in turn -- only
	# worth the minutes it takes when the tree is most of the frame, which in
	# the air it is not and on foot it is.
	if rows.size() > 0 and float((rows[rows.size() - 1] as Array)[1]) > floor_ms * 0.5:
		for c in world.get_children():
			if not (c is Node) or c.get_child_count() < 1:
				continue
			var was_mode: int = (c as Node).process_mode
			await probe.call("  %s, not processing" % String(c.name),
				func() -> void:
					(c as Node).process_mode = Node.PROCESS_MODE_DISABLED,
				func() -> void:
					(c as Node).process_mode = was_mode as Node.ProcessMode)
	# And how much of the floor is simply pixels. Everything above is per pixel
	# or per screen; if half resolution halves it, the answer is fill rate and
	# no amount of taking things out of the tree will touch it.
	await probe.call("three quarters of the pixels",
		func() -> void: vp.scaling_3d_scale = 0.5,
		func() -> void: vp.scaling_3d_scale = 1.0)
	for nd in everything:
		if is_instance_valid(nd):
			(nd as Node3D).visible = true
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var acc := 0.0
	print("[cost] and what is in the %.2f ms floor, with the world hidden:" % floor_ms)
	for r in rows:
		var rr: Array = r
		if absf(float(rr[1])) < 0.05:
			continue
		# The resolution probe is not a thing that can be removed; it says how
		# much of the floor is fill rate, which overlaps everything above it.
		if String(rr[0]) != "three quarters of the pixels":
			acc += maxf(float(rr[1]), 0.0)
		print("[cost]   %-26s %6.2f ms" % [String(rr[0]), float(rr[1])])
	if acc * 4.0 < floor_ms:
		# Every one of them measured nothing, and that is the finding.
		#
		# The sky, its radiance, the glow, the fog, the shadow map,
		# multisampling, screen space AA, the instruments, physics, the whole
		# tree paused, and the largest branch of the world taken out of the tree
		# rather than merely hidden: none of it moves this. Three quarters of
		# the pixels is the only probe that ever does, and only by about a
		# sixth. Whatever the floor is, it is not something switched on in here
		# -- so there is nothing in the game to take out of it, and a change
		# that wants to be seen has to be bigger than it.
		print("[cost]   nothing above accounts for it: the floor is not the game's")

## Median frame time over a short run, in milliseconds.
##
## The median, not the mean: one 100 ms stall in a sample of thirty-two moves a
## mean by 2.6 ms, which is larger than most of the things being measured, and
## the first pass at this reported several subjects as costing *less* than
## nothing for exactly that reason.
func _time_frames(n := 64) -> float:
	# A few frames to settle first: hiding a node re-batches, and the frame it
	# happens in is not representative of anything.
	for _s in 8:
		await world.get_tree().process_frame
	# The clock, not the delta the frame was handed.
	#
	# `get_process_delta_time` is what the engine tells `_process` a frame took,
	# and it is not the same number as the time between two frames: it is
	# smoothed, and on a machine holding a steady rate it reads steady whatever
	# is switched on or off. Measured through it, every probe in the floor
	# census came back under a twentieth of a millisecond -- the sky, the glow,
	# the shadow map, physics, even pausing the whole tree -- which is not a
	# result, it is an instrument reading zero.
	var got: Array = []
	var last := Time.get_ticks_usec()
	for _i in n:
		await world.get_tree().process_frame
		var now := Time.get_ticks_usec()
		got.append(float(now - last) * 0.001)
		last = now
	got.sort()
	return float(got[int(got.size() / 2.0)])
#endregion


#region --planettest
var _planet_test := false

# The planet body, and the hand-over between it and the ground.
func tick_planet() -> bool:
	if _planet_test:
		_planet_test = false
		_run_planet_test()
		world.get_tree().quit()
		return true
	return false

## The planet body: does the sphere sit where the ground does, and does the
## hand-over between the two happen where it is supposed to?
##
## The two failures worth catching are a sphere that does not agree with the
## terrain it replaces — which reads as the world stepping up or down as it
## fades — and a hand-over that never happens, which is the whole point of it.
func _run_planet_test() -> void:
	if not is_instance_valid(world.planet):
		print("[planet] RESULT: FAILED — no planet body was built")
		return
	var mi := world.planet.get_node_or_null("PlanetBody") as MeshInstance3D
	if mi == null or mi.mesh == null:
		print("[planet] RESULT: FAILED — the body has no mesh")
		return
	var tris: int = int(mi.mesh.get_faces().size() / 3.0)
	print("[planet] body: %d triangles, %d rings, %d segments" % [
		tris, world.planet._ring_angles().size(), Planet.SEGS])
	# Where the drawn sphere actually is over the theatre, against sea level.
	# The vertices are on the sphere by construction; what can be wrong is the
	# flat triangle between them, which sags by more the coarser the rings are.
	# Sampled at the middle of a face, which is where that sag is worst.
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var faces: PackedVector3Array = mi.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var face_mid: Vector3 = (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		var w: Vector3 = face_mid + world.planet.position
		# Only where there is ground to agree with -- which means the mapped
		# square *and* the near side of the planet. Tested on x and z alone the
		# antipode passes too, and the far pole's triangles are 200 km across:
		# the worst standoff reported was 769 m on the other side of the world.
		if absf(w.x) > Sim.WORLD_HALF or absf(w.z) > Sim.WORLD_HALF \
				or Sim.up_at(w).y < 0.9:
			continue
		var off: float = absf(w.distance_to(Sim.planet_centre) - Sim.PLANET_R)
		if off > worst:
			worst = off
			worst_at = Vector2(w.x, w.z)
	print("[planet] over the theatre the drawn sphere stands off sea level by at most %.1f m (at %s, %.0f km out)" % [
		worst, str(worst_at.round()), worst_at.length() * 0.001])
	# The generated planet. What is being checked is that there is a planet there
	# at all -- unique ground the whole way round rather than the theatre
	# repeated -- that it has sea and land in something like the proportions a
	# planet has, and that the theatre appears on it exactly once.
	var gen: PlanetTerrain = world.planet.terrain_gen
	var land := 0
	var total := 0
	var hi := -1e9
	var lo := 1e9
	for j in 64:
		for i in 128:
			var d := world.planet.sheet_dir((float(i) + 0.5) / 128.0,
				(float(j) + 0.5) / 64.0)
			var h: float = gen.elevation(d)
			total += 1
			if h > 0.0:
				land += 1
			hi = maxf(hi, h)
			lo = minf(lo, h)
	print("[planet] the generated planet is %d%% land, from %.0f m down to %.0f m" % [
		int(round(100.0 * float(land) / maxf(float(total), 1.0))), hi, lo])
	# Unique, not tiled: two points a quarter of the planet apart on the same
	# parallel must not be the same ground.
	var same := 0
	for k in 48:
		var a: float = TAU * float(k) / 48.0
		var d1 := world.planet.sheet_dir(fmod(a / TAU, 1.0), 0.42)
		var d2 := world.planet.sheet_dir(fmod(a / TAU + 0.25, 1.0), 0.42)
		if absf(gen.elevation(d1) - gen.elevation(d2)) < 1.0:
			same += 1
	print("[planet] of 48 pairs a quarter of the planet apart, %d are the same ground" % same)
	# The theatre is a real place on it, and only one place.
	# The middle of the chart, which is wherever this sortie began. `Vector3.UP`
	# was the airfield for as long as there was one airfield; there are six
	# countries now and the chart is put on the one being flown for.
	var here: float = gen.elevation(Sim.chart_origin)
	var cap: float = Sim.height_at(0.0, 0.0) - Sim.sea_at(0.0, 0.0)
	var anti: float = gen.elevation(-Sim.chart_origin)
	var anti_cap: bool = absf(anti - cap) < 1.0
	print("[planet] at the airfield the planet stands %.1f m, the height field says %.1f m; the antipode is a copy: %s" % [
		here, cap, str(anti_cap)])
	# The hand-over. A scratch camera, so the one being flown is left alone.
	var probe := Camera3D.new()
	world.add_child(probe)
	var rows: Array = []
	var ok_band := true
	for alt in [0.0, 20_000.0, Planet.FADE_LO, 55_000.0, 64_000.0, 80_000.0,
			Planet.FADE_HI, 140_000.0]:
		probe.global_position = Vector3(0.0, Sim.sea_surface(0.0, 0.0) + float(alt), 0.0)
		world.planet.follow(probe, world.terrain, world.scenery)
		rows.append([alt, world.planet.fade, world.planet.dormant, probe.far,
			(world.terrain as Node3D).visible])
		print("[planet] %6.0f km up: body %.2f, ground %.2f, far %5.0f km, chunks %s" % [
			float(alt) * 0.001, world.planet.fade, 1.0 - world.planet.fade,
			probe.far * 0.001, "up" if (world.terrain as Node3D).visible else "down"])
	probe.queue_free()
	# Nothing at the bottom, everything at the top, and monotonic in between:
	# a crossfade that goes backwards anywhere shows as the ground flickering.
	var prev := -1.0
	for r in rows:
		if float(r[1]) < prev - 0.0001:
			ok_band = false
		prev = float(r[1])
	var low: Array = rows[0]
	var high: Array = rows[rows.size() - 1]
	var band: Array = rows[3]
	var crossfades: bool = float(band[1]) > 0.05 and float(band[1]) < 0.95 \
		and bool(band[4])
	print("[planet] RESULT: %s" % ("ok" if worst < 60.0 and tris > 10000
		and float(low[1]) < 0.001 and not bool(low[2])
		and float(high[1]) > 0.999 and bool(high[2]) and not bool(high[4])
		and absf(float(high[3]) - Planet.FAR_HI) < 1.0 and crossfades and ok_band
		and land > 8 and land < int(float(total) * 0.5) and same == 0
		and absf(here - cap) < 1.0 and not anti_cap
		else "FAILED"))
#endregion


#region --skytest
var _sky_test := false
var _sky_short := 0

# The sky: how much cloud there is, how it is banded, and where the sun
# goes over a day.
func tick_sky() -> void:
	if _sky_test:
		_sky_test = false
		# The shader itself: headless never rasterises, so ask the compiler
		# directly rather than assuming a clean parse means a clean sky.
		var probe_sh := Shader.new()
		probe_sh.code = Weather.SKY_SHADER
		var unis := probe_sh.get_shader_uniform_list()
		var names := PackedStringArray()
		for u in unis:
			names.append(String(u["name"]))
		# A shader that fails to compile reports no uniforms at all and then
		# quietly draws nothing. That is not something to print and move past:
		# an array literal in the march cost a whole sky exactly this way.
		if unis.size() < 15:
			_sky_short += 1
		print("[sky] shader compiled with %d uniforms: %s" % [unis.size(),
			", ".join(names)])
		var fog_sh := Shader.new()
		fog_sh.code = Weather.FOG_SHADER
		if fog_sh.get_shader_uniform_list().size() < 6:
			_sky_short += 1
		print("[sky] fog shader compiled with %d uniforms; volume %s, box %s, froxel reach %.0f m" % [
			fog_sh.get_shader_uniform_list().size(),
			"present" if world.weather.has_volume() else "MISSING",
			str(world.weather.volume_size()), world._env.volumetric_fog_length])
		var eye0 := world.get_viewport().get_camera_3d()
		if eye0 != null:
			world.weather.follow(eye0.global_position)
		print("[sky] eye handed to the sky: %s (current camera %s), march limit %.0f m" % [
			str(world._psm.get_shader_parameter("cam_pos")),
			String(eye0.name) if eye0 != null else "none",
			float(world._psm.get_shader_parameter("march_far"))])
		for id in Weather.ids():
			world.set_weather(id)
			var decks := 0
			for d in world.weather.get_children():
				if d is MultiMeshInstance3D:
					decks += 1
			var band: Vector2 = world.weather.cloud_band()
			var reach: float = world.weather.march_reach(id)
			if reach < Weather.MARCH_FAR:
				_sky_short += 1
			print("[sky] %-10s coverage %.2f, density %.2f, %d steps reaching %6.0f m of %.0f; cloud %.0f to %.0f m; %d draw calls, %d billboards" % [
				id, float(world._psm.get_shader_parameter("coverage")),
				float(world._psm.get_shader_parameter("density_mul")),
				int(world._psm.get_shader_parameter("steps")), reach, Weather.MARCH_FAR,
				band.x, band.y, decks, world.weather.puff_count()])
		print("[sky] RESULT: %s" % ("ok" if _sky_short == 0 else
			"FAILED — %d fault(s): a shader that did not compile, or a preset that cannot march as far as it claims" % _sky_short))
		world.set_weather("scattered")
		print("[sky] a day, by the solar model:")
		for h in [0, 4, 6, 8, 12, 16, 18, 20, 22]:
			var sa := world.weather.solar_angles(float(h))
			world.weather.time_of_day = float(h)
			world.weather._apply_sun(true)
			print("[sky]   %02d:00  sun %+5.1f deg elevation, bearing %5.1f, light %.2f, ambient %.2f, daylight %.2f" % [
				h, rad_to_deg(sa.x), rad_to_deg(sa.y), world._sun.light_energy,
				world._env.ambient_light_energy, world.weather.daylight()])
		world.get_tree().quit()
#endregion


#region --geomtest
var _geomtest := false

func tick_geomtest() -> void:
	if _geomtest:
		_geomtest = false
		var bad := 0
		for id in JetSpec.ids():
			var sp := JetSpec.get_spec(id)
			var m := JetFactory.build(sp)
			var root: Node3D = m["root"]
			world.add_child(root)
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := -lo
			for mi in _all_mesh_children(root):
				var ab: AABB = (mi as MeshInstance3D).mesh.get_aabb()
				var o: Vector3 = (mi as MeshInstance3D).position
				lo = lo.min(ab.position + o)
				hi = hi.max(ab.position + ab.size + o)
			var built_span := hi.x - lo.x
			var built_len := hi.z - lo.z
			# A helicopter's widest thing is its rotor disc, not the stub wing
			# that `span` refers to. Comparing the two called every rotary
			# airframe broken by a factor of three.
			var rotary: bool = sp.has("rotor_radius")
			var want: float = (float(sp["rotor_radius"]) * 2.0) if rotary \
				else float(sp["span"])
			var what := "rotor" if rotary else "span "
			var err := absf(built_span - want) / maxf(want, 1.0)
			var flag := ""
			if err > 0.18:
				flag = "  <- DOES NOT MATCH"
				bad += 1
			print("[geom] %-8s %s built %6.1f m vs spec %6.1f m (%+5.1f%%), length %6.1f m%s" % [
				id, what, built_span, want, err * 100.0, built_len, flag])
			root.queue_free()
		print("[geom] RESULT: %s" % ("ok" if bad == 0 else
			"FAILED — %d airframe(s) do not match their own dimensions" % bad))
		world.get_tree().quit()
#endregion


#region --culltest
var _culltest := false

# Does the model each aeroplane builds match the numbers it flies on? A wing
# polygon written on the wrong axes builds a stub with ten metres of chord
# and nothing anywhere says so — the aerodynamics keep using the spec.
# See-through parts. A closed solid presents a front face to any ray that
# enters it; if the nearest triangle a ray meets is facing away, that pixel
# looks straight through the skin, which is what you see from some angles
# on the engines and nacelles.
func tick_culltest() -> bool:
	if _culltest:
		_culltest = false
		_run_culltest()
		world.get_tree().quit()
		return true
	return false

## Harness for the commander's sight. Everything here used to be impossible:
## the page force-closed itself on any frame a tank was crewed.

## Gather every triangle of a built model in model space: positions and the
## normal the mesh actually stores for each vertex.
func _tris_of(root: Node3D) -> Array:
	var out: Array = []
	for n in _all_mesh_children(root):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			# A surface drawn with culling off cannot show through: the back of
			# the face is rendered. Counting the rotor disc as a hole put every
			# helicopter above twenty per cent for no visible reason.
			var sm := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if sm != null and sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
				continue
			var arr: Array = mi.mesh.surface_get_arrays(si)
			if arr.is_empty():
				continue
			var rawv: Variant = arr[Mesh.ARRAY_VERTEX]
			if rawv == null:
				continue
			var vs: PackedVector3Array = rawv
			var rawn: Variant = arr[Mesh.ARRAY_NORMAL]
			var ns := PackedVector3Array()
			if rawn != null:
				ns = rawn
			# an unindexed surface is a plain triangle soup
			var idx := PackedInt32Array()
			var rawi: Variant = arr[Mesh.ARRAY_INDEX]
			if rawi != null:
				idx = rawi
			if idx.is_empty():
				idx = PackedInt32Array(range(vs.size()))
			var k := 0
			while k + 2 < idx.size():
				var a: Vector3 = xf * vs[idx[k]]
				var b: Vector3 = xf * vs[idx[k + 1]]
				var c: Vector3 = xf * vs[idx[k + 2]]
				var nn := Vector3.ZERO
				if ns.size() > idx[k]:
					nn = (xf.basis * ns[idx[k]]).normalized()
				if nn.length_squared() < 0.5:
					nn = (b - a).cross(c - a).normalized()
				out.append([a, b, c, nn, mi.name])
				k += 3
	return out

## Fire rays at a model from all round it and report how many meet a face that
## is pointing away from the camera first -- a hole you can see through.
func _see_through(tris: Array, aabb: AABB, rays: int, trace := false) -> Array:
	var mid: Vector3 = aabb.position + aabb.size * 0.5
	var radius: float = aabb.size.length() * 0.6 + 1.0
	var hits := 0
	var through := 0
	var who: Dictionary = {}
	var g := 1.0 + sqrt(5.0)
	for i in rays:
		# a spiral over the sphere, so the sample directions are even
		var t: float = float(i) / float(rays)
		var incl: float = acos(1.0 - 2.0 * (t + 0.5 / float(rays)))
		var azim: float = TAU * float(i) / g
		var dir := Vector3(sin(incl) * cos(azim), cos(incl), sin(incl) * sin(azim))
		# aim a little off centre so the ray crosses skin, not just the axis
		var jitter := Vector3(sin(azim * 3.1), cos(incl * 2.7), sin(incl * 4.3))
		var aim: Vector3 = mid + jitter * aabb.size * 0.22
		var from: Vector3 = mid + dir * radius
		var ray: Vector3 = (aim - from).normalized()
		var best := 1e9
		var best_n := Vector3.ZERO
		var best_who := ""
		for tri in tris:
			var hit = Geometry3D.ray_intersects_triangle(from, ray, tri[0], tri[1], tri[2])
			if hit == null:
				continue
			var d: float = from.distance_to(hit)
			if d < best:
				best = d
				best_n = tri[3]
				best_who = "%s@%s" % [str(tri[4]),
					str(((tri[0] + tri[1] + tri[2]) / 3.0).round())]
		if best > 1e8:
			continue
		hits += 1
		if best_n.dot(ray) > 0.02:
			through += 1
			who[best_who] = int(who.get(best_who, 0)) + 1
			if trace and through <= 2:
				# what else is on this line, so an open duct can be told apart
				# from a panel that is simply wound the wrong way
				var seq := PackedStringArray()
				var order: Array = []
				for tri in tris:
					var h2 = Geometry3D.ray_intersects_triangle(from, ray, tri[0], tri[1], tri[2])
					if h2 != null:
						order.append([from.distance_to(h2), tri[3],
							"%s@%s" % [str(tri[4]), str(((tri[0] + tri[1] + tri[2]) / 3.0 * 10.0).round() / 10.0)]])
				order.sort_custom(func(x, y): return x[0] < y[0])
				for k in mini(5, order.size()):
					seq.append("%.2fm %s n=%s n.ray=%+.2f" % [order[k][0], order[k][2],
						str(((order[k][1] as Vector3) * 100.0).round() / 100.0),
						(order[k][1] as Vector3).dot(ray)])
				print("[cull]    ray from %s dir %s: %s" % [
					str(from.round()), str((ray * 100.0).round() / 100.0), " | ".join(seq)])
	return [hits, through, who]

## One model's worth of see-through sampling, reported the same way as an
## airframe. Returns [rays that hit, rays that see through, per cent].
func _cull_of(root: Node3D, rays: int) -> Array:
	var tris := _tris_of(root)
	if tris.is_empty():
		print("[cull] %-9s no mesh" % str(root.name))
		return [0, 0, 0.0]
	var ab := AABB()
	var first := true
	for tri in tris:
		for v in [tri[0], tri[1], tri[2]]:
			if first:
				ab = AABB(v, Vector3.ZERO)
				first = false
			else:
				ab = ab.expand(v)
	var r := _see_through(tris, ab, rays)
	var pc: float = 100.0 * float(r[1]) / maxf(float(r[0]), 1.0)
	var blame: Dictionary = r[2]
	var parts := PackedStringArray()
	for k in blame:
		parts.append("%s x%d" % [k, int(blame[k])])
	var nm := str(root.name)
	if root.has_method("display_name"):
		nm = String(root.call("display_name"))
	print("[cull] %-9s %5d tris, %3d/%3d rays meet a face turned away (%4.1f%%)%s" % [
		nm.left(9), tris.size(), r[1], r[0], pc,
		("   " + ", ".join(parts)) if parts.size() > 0 else ""])
	return [r[0], r[1], pc]

func _run_culltest() -> void:
	var rays := 220
	var worst := ""
	var worst_pc := 0.0
	var total := 0
	var total_through := 0
	for id in JetSpec.ids():
		var sp := JetSpec.get_spec(id)
		var m := JetFactory.build(sp)
		var root: Node3D = m["root"]
		world.add_child(root)
		var tris := _tris_of(root)
		var ab := AABB()
		var first := true
		for tri in tris:
			for v in [tri[0], tri[1], tri[2]]:
				if first:
					ab = AABB(v, Vector3.ZERO)
					first = false
				else:
					ab = ab.expand(v)
		var r := _see_through(tris, ab, rays)
		var pc: float = 100.0 * float(r[1]) / maxf(float(r[0]), 1.0)
		total += int(r[0])
		total_through += int(r[1])
		if pc > worst_pc:
			worst_pc = pc
			worst = id
		var blame: Dictionary = r[2]
		var parts := PackedStringArray()
		for k in blame:
			parts.append("%s x%d" % [k, int(blame[k])])
		print("[cull] %-9s %5d tris, %3d/%3d rays meet a face turned away (%4.1f%%)%s" % [
			id, tris.size(), r[1], r[0], pc,
			("   " + ", ".join(parts)) if parts.size() > 0 else ""])
		root.queue_free()
	# and the same for the things you drive and sail, which are built out of the
	# same helpers
	for kind in VehicleSpec.KINDS.keys():
		var tv := Tank.new()
		tv.setup(0, str(kind))
		world.add_child(tv)
		var r2 := _cull_of(tv, rays)
		total += int(r2[0])
		total_through += int(r2[1])
		if float(r2[2]) > worst_pc:
			worst_pc = float(r2[2])
			worst = str(kind)
		tv.queue_free()
	for kind in Ship.KINDS.keys():
		var sv := Ship.new()
		sv.setup(str(kind), 0)
		world.add_child(sv)
		var r3 := _cull_of(sv, rays)
		total += int(r3[0])
		total_through += int(r3[1])
		if float(r3[2]) > worst_pc:
			worst_pc = float(r3[2])
			worst = str(kind)
		sv.queue_free()
	var overall: float = 100.0 * float(total_through) / maxf(float(total), 1.0)
	print("[cull] overall %d/%d rays see through the skin (%.1f%%), worst %s at %.1f%%" % [
		total_through, total, overall, worst, worst_pc])
	print("[cull] RESULT: %s" % ("ok" if overall < 0.35 else "FAILED"))
#endregion


#region Shared within this group

## Every MeshInstance3D under a node.
func _all_mesh_children(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append(c)
		out.append_array(_all_mesh_children(c))
	return out
#endregion
