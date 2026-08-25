class_name JetFactory
## Turns a JetSpec entry into a faceted low-poly airframe plus every moving part
## the flight model needs to drive: stabilators, gear legs, bay doors, stores
## and afterburner cones.

static func build(spec: Dictionary) -> Dictionary:
	var sh: Dictionary = spec["shape"]
	var paint: Color = sh["paint"]
	var dark: Color = sh["dark"]
	var mat_paint := MeshKit.panelled(paint, 0.42, 0.06, 1.9)
	var mat_dark := MeshKit.mat(dark, 0.62, 0.10)
	var mat_glass := MeshKit.mat(sh["glass"], 0.12, 0.65)
	mat_glass.emission_enabled = true
	mat_glass.emission = Color(0.16, 0.13, 0.05)
	mat_glass.rim_enabled = true
	mat_glass.rim = 0.8

	var root := Node3D.new()
	root.name = "Model"
	var out := {"root": root, "doors": {}, "stores": {}, "gear": [], "ab": [], "nozzles": [],
				"stabs": [], "lights": [], "flaps": [], "ailerons": [], "rudders": [],
				"wheels": [], "cockpit_parts": [], "parts": {}, "canards": [], "props": [], "burners": [], "rotors": []}

	# ---------------------------------------------------------------- body
	var st := MeshKit.begin()
	var rings := []
	var sections: Array = sh["sections"]
	var cp0: Dictionary = sh["canopy"]
	var cz_a: float = minf(float(cp0["z0"]), float(cp0["z1"])) - 0.5
	var cz_b: float = maxf(float(cp0["z0"]), float(cp0["z1"])) + 0.3
	# Extra stations through the cockpit so the trough below has something to be
	# cut into: two rings over four metres makes a slot, not a cockpit.
	var stations: Array = []
	for i in sections.size():
		stations.append(sections[i])
		if i + 1 < sections.size():
			var z0: float = sections[i][0]
			var z1: float = sections[i + 1][0]
			if maxf(z0, z1) > cz_a and minf(z0, z1) < cz_b:
				var nsteps := int(absf(z1 - z0) / 0.6)
				for k in range(1, nsteps):
					var f := float(k) / float(nsteps)
					var mid: Array = []
					for c in 5:
						mid.append(lerpf(float(sections[i][c]), float(sections[i + 1][c]), f))
					stations.append(mid)
	for s in stations:
		rings.append(MeshKit.ring(s[1], s[2], s[3], s[0], s[4], 12))
	_cut_cockpit(rings, cz_a, cz_b, float(cp0["y"]) - 0.62)
	MeshKit.loft(st, rings, Vector3(0, 0, sections[int(sections.size() * 0.5)][0]))

	# wings: the trailing edge is carved off and rebuilt as hinged flaperons
	var wing: Dictionary = sh["wing"].duplicate(true)
	var wspan: float = spec["span"]
	var c_root: float = 0.048 * wspan
	var c_tip: float = 0.030 * wspan
	var raw_poly: Array = wing["poly"]
	var te_tip: Vector2 = raw_poly[raw_poly.size() - 2]
	var te_root: Vector2 = raw_poly[raw_poly.size() - 1]
	var cut: Array = raw_poly.duplicate()
	cut[cut.size() - 2] = te_tip - Vector2(0.0, c_tip)
	cut[cut.size() - 1] = te_root - Vector2(0.0, c_root)
	wing["poly"] = cut
	# ventral strakes stay part of the shell
	for f in sh.get("vents", []):
		_add_fin(st, f, 1.0)
		_add_fin(st, f, -1.0)
	# vertical tails
	for f in sh.get("fins", []):
		var fin: Dictionary = f.duplicate(true)
		var fp: Array = fin["poly"]
		# poly is (z, height) ordered root-fwd, tip-fwd, tip-aft, root-aft
		var hinge_root: float = lerpf(fp[0].x, fp[3].x, 0.66)
		var hinge_tip: float = lerpf(fp[1].x, fp[2].x, 0.66)
		fin["poly"] = [fp[0], fp[1], Vector2(hinge_tip, fp[2].y), Vector2(hinge_root, fp[3].y)]
		var fin_sides: Array = [1.0, -1.0] if f["x"] > 0.001 else [1.0]
		for fs in fin_sides:
			var fst := MeshKit.begin()
			_add_fin(fst, fin, fs)
			var fnode := MeshKit.mi(MeshKit.finish(fst, mat_paint),
				"Fin" + ("R" if fs > 0 else "L"))
			root.add_child(fnode)
			out["parts"]["fin_" + ("r" if fs > 0 else "l")] = fnode
	# intakes: a lofted duct with a raked lip and a boundary layer splitter,
	# rather than a box stuck on the side
	for it in sh.get("intakes", []):
		var ipos: Vector3 = it["pos"]
		var isz: Vector3 = it["size"]
		var iyaw: float = deg_to_rad(float(it.get("yaw", 0.0)))
		if ipos.x > 0.01:
			_add_intake(st, ipos, isz, iyaw, 1.0, String(it.get("style", "caret")))
			_add_intake(st, Vector3(-ipos.x, ipos.y, ipos.z), isz, -iyaw, -1.0,
				String(it.get("style", "caret")))
		else:
			_add_intake(st, ipos, isz, iyaw, 1.0, String(it.get("style", "chin")))
	root.add_child(MeshKit.mi(MeshKit.finish(st, mat_paint), "Airframe"))

	for wside in [1.0, -1.0]:
		var wst := MeshKit.begin()
		_add_planform(wst, wing, wside)
		var wnode := MeshKit.mi(MeshKit.finish(wst, mat_paint),
			"Wing" + ("R" if wside > 0 else "L"))
		root.add_child(wnode)
		out["parts"]["wing_" + ("r" if wside > 0 else "l")] = wnode

	# ---------------------------------------------------- flaps and ailerons
	for side in [1.0, -1.0]:
		var wy: float = wing["y"]
		var hr := Vector3(te_root.x * side, wy, te_root.y - c_root)
		var ht := Vector3(te_tip.x * side, wy, te_tip.y - c_tip)
		var rr := Vector3(te_root.x * side, wy, te_root.y)
		var rt := Vector3(te_tip.x * side, wy, te_tip.y)
		for part in [[0.0, 0.52, "Flap"], [0.52, 1.0, "Aileron"]]:
			var t0: float = part[0]
			var t1: float = part[1]
			var quad := PackedVector3Array([
				hr.lerp(ht, t0), hr.lerp(ht, t1), rr.lerp(rt, t1), rr.lerp(rt, t0)])
			# The hinge line runs outboard, so the two wings' axes point in
			# opposite world directions. That is exactly what an aileron wants
			# and exactly what a flap does not: both flaps must go down
			# together, so the left one's axis is flipped to match the right.
			var axis := (ht - hr).normalized()
			if String(part[2]) == "Flap" and side < 0.0:
				axis = -axis
			var node := _hinged(quad, hr.lerp(ht, t0), axis, Vector3.UP,
				lerpf(0.10, 0.06, t0), mat_paint, str(part[2]))
			root.add_child(node)
			if part[2] == "Flap":
				out["flaps"].append(node)
			else:
				out["ailerons"].append({"node": node, "side": side})

	# ---------------------------------------------------------------- rudders
	for f in sh.get("fins", []):
		var sides: Array = [1.0, -1.0] if f["x"] > 0.001 else [1.0]
		for side in sides:
			var fp: Array = f["poly"]
			var cant: float = deg_to_rad(float(f["cant"])) * float(side)
			var up_f := Vector3(sin(cant), cos(cant), 0.0)
			var fwd_f := Vector3(0, 0, 1)
			var org := Vector3(f["x"] * side, 0, 0)
			var conv := func(pt: Vector2) -> Vector3:
				return org + fwd_f * pt.x + up_f * pt.y
			var h_root: float = lerpf(fp[0].x, fp[3].x, 0.66)
			var h_tip: float = lerpf(fp[1].x, fp[2].x, 0.66)
			var p_root: Vector3 = conv.call(Vector2(h_root, fp[3].y))
			var p_tip: Vector3 = conv.call(Vector2(h_tip, fp[2].y))
			var quad := PackedVector3Array([p_root, p_tip,
				conv.call(fp[2]), conv.call(fp[3])])
			var nrm := fwd_f.cross(up_f).normalized()
			var node := _hinged(quad, p_root, (p_tip - p_root).normalized(), nrm,
				f["t"] * 0.42, mat_paint, "Rudder")
			node.set_meta("side", side)
			root.add_child(node)
			out["rudders"].append(node)

	# ---------------------------------------------------------------- canopy
	var cp: Dictionary = sh["canopy"]
	var opens: bool = bool(spec.get("canopy_opens", true))
	var hinge_pt := Vector3(0.0, cp["y"], cp["z1"] + 0.15)
	var canopy_hinge := Node3D.new()
	canopy_hinge.name = "CanopyHinge"
	canopy_hinge.position = hinge_pt
	root.add_child(canopy_hinge)
	if opens:
		out["canopy"] = canopy_hinge
		out["parts"]["canopy"] = canopy_hinge
	var cst := MeshKit.begin()
	# A transport or a gunship has a flight deck with windows let into the nose,
	# not a blown bubble sitting proud of the spine. Anything that does not open
	# its hood gets glazing that follows the fuselage instead.
	if not opens:
		var gz0: float = cp["z0"]
		var gz1: float = cp["z1"]
		var gy: float = cp["y"]
		var gw: float = cp["w"]
		var panes := 5
		for i in panes:
			var f0 := float(i) / float(panes)
			var f1 := float(i + 1) / float(panes)
			var a0: float = lerpf(-1.05, 1.05, f0)
			var a1: float = lerpf(-1.05, 1.05, f1)
			var p0 := Vector3(sin(a0) * gw, gy + cos(a0) * 0.30, gz0)
			var p1 := Vector3(sin(a1) * gw, gy + cos(a1) * 0.30, gz0)
			var q0 := Vector3(sin(a0) * gw * 0.92, gy + cos(a0) * 0.26, gz1)
			var q1 := Vector3(sin(a1) * gw * 0.92, gy + cos(a1) * 0.26, gz1)
			MeshKit.quad(cst, p0, p1, q1, q0, Vector3(0, gy, (gz0 + gz1) * 0.5))
	else:
		var crings := []
		var steps := 9
		for i in steps + 1:
			var t := float(i) / float(steps)
			var z: float = lerpf(cp["z0"], cp["z1"], t)
			var k := pow(sin(PI * clampf(t * 0.94 + 0.06, 0.0, 1.0)), 0.55)
			crings.append(MeshKit.ring(cp["w"] * k, cp["h"] * k, cp["y"], z, 2.4, 10))
		MeshKit.loft(cst, crings, Vector3(0, cp["y"], (cp["z0"] + cp["z1"]) * 0.5))
	var canopy_mi := MeshKit.mi(MeshKit.finish(cst, mat_glass), "Canopy")
	canopy_mi.position = -hinge_pt
	canopy_hinge.add_child(canopy_mi)

	# boarding ladder, shown while the canopy is up
	var lad := MeshKit.begin()
	var lx: float = -(cp["w"] + 0.85)
	var lz: float = lerpf(cp["z0"], cp["z1"], 0.62)
	for i in 4:
		var yy: float = cp["y"] - 0.55 - float(i) * 0.46
		MeshKit.box(lad, Vector3(0.44, 0.05, 0.13), Vector3(lx, yy, lz))
	MeshKit.box(lad, Vector3(0.07, 2.1, 0.07), Vector3(lx - 0.20, cp["y"] - 1.25, lz))
	MeshKit.box(lad, Vector3(0.07, 2.1, 0.07), Vector3(lx + 0.20, cp["y"] - 1.25, lz))
	var lad_mi := MeshKit.mi(MeshKit.finish(lad, MeshKit.mat(Color(0.72, 0.70, 0.20), 0.7, 0.2)), "Ladder")
	lad_mi.visible = false
	root.add_child(lad_mi)
	if opens:
		out["ladder"] = lad_mi
		out["ladder_pos"] = Vector3(lx - 0.55, 0.0, lz)
	else:
		# airliners and transports board through a door on the forward left
		var door := MeshKit.begin()
		var dz: float = lerpf(cp["z0"], cp["z1"], 0.75) + 1.2
		var dw: float = 0.0
		for sec in sections:
			if absf(sec[0] - dz) < 3.0:
				dw = maxf(dw, sec[1])
		MeshKit.box(door, Vector3(0.10, 1.85, 0.85), Vector3(-dw + 0.05, cp["y"] - 1.35, dz))
		var dmi := MeshKit.mi(MeshKit.finish(door,
			MeshKit.mat(Color(0.20, 0.21, 0.23), 0.7, 0.1)), "Door")
		root.add_child(dmi)
		out["ladder_pos"] = Vector3(-dw - 1.1, 0.0, dz)

	# ---------------------------------------------------------------- nozzles
	# A vectoring aircraft gets each nozzle on its own pivot so it can actually
	# swivel; everything else keeps them baked into the one mesh.
	var vector_nozzles: bool = float(spec.get("tvc_pitch", 0.0)) > 0.0 \
		or float(spec.get("tvc_yaw", 0.0)) > 0.0
	var nst := MeshKit.begin()
	var nozzles: Array = sh["nozzles"]
	var round_nozzle: bool = sh["nozzle_kind"] == "round"
	var nr := 0.62 if round_nozzle else 0.55
	for n_i in nozzles.size():
		var n: Vector3 = nozzles[n_i] if not vector_nozzles else Vector3.ZERO
		var nst_local := MeshKit.begin() if vector_nozzles else nst
		if round_nozzle:
			# convergent-divergent can: shroud, feathered petals, then the throat
			MeshKit.cone(nst_local, nr * 1.16, nr * 1.10, -1.7, -0.55, n, 14, false)
			var petals := 12
			for i in petals:
				var a0 := TAU * float(i) / float(petals)
				var a1 := TAU * float(i + 0.82) / float(petals)
				var r_in := nr * 1.10
				var r_out := nr * 0.80
				var quad := PackedVector3Array([
					n + Vector3(cos(a0) * r_in, sin(a0) * r_in, -0.55),
					n + Vector3(cos(a1) * r_in, sin(a1) * r_in, -0.55),
					n + Vector3(cos(a1) * r_out, sin(a1) * r_out, 0.62),
					n + Vector3(cos(a0) * r_out, sin(a0) * r_out, 0.62)])
				MeshKit.quad(nst_local, quad[0], quad[1], quad[2], quad[3], n)
			MeshKit.cone(nst_local, nr * 0.78, nr * 0.66, 0.62, 1.05, n, 12, false)
		else:
			# two dimensional vectoring nozzle: flat upper and lower ramps
			var hw := nr * 0.92
			for sy in [-1.0, 1.0]:
				var ramp := PackedVector2Array([Vector2(-hw, -1.5), Vector2(hw, -1.5),
					Vector2(hw * 0.86, 0.75), Vector2(-hw * 0.86, 0.75)])
				MeshKit.prism(nst_local, ramp, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
					PackedFloat32Array([0.07, 0.07, 0.05, 0.05]),
					n + Vector3(0, sy * nr * 0.72, 0))
			for sx in [-1.0, 1.0]:
				var side := PackedVector2Array([Vector2(-nr * 0.80, -1.5), Vector2(nr * 0.80, -1.5),
					Vector2(nr * 0.66, 0.75), Vector2(-nr * 0.66, 0.75)])
				MeshKit.prism(nst_local, side, Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0),
					PackedFloat32Array([0.06, 0.06, 0.05, 0.05]), n + Vector3(sx * hw, 0, 0))
		if vector_nozzles:
			var pivot := Node3D.new()
			pivot.name = "Nozzle%d" % n_i
			pivot.position = nozzles[n_i]
			pivot.add_child(MeshKit.mi(MeshKit.finish(nst_local, mat_dark), "Can"))
			root.add_child(pivot)
			out["nozzles"].append(pivot)
	# nose probe
	MeshKit.cone(nst, 0.05, 0.005, 0.0, -1.1, Vector3(0, sections[0][3], sections[0][0]), 6)
	root.add_child(MeshKit.mi(MeshKit.finish(nst, mat_dark), "Nozzles"))

	var glow_mat := MeshKit.mat(Color(0.05, 0.03, 0.02), 0.4, 0.0, Color(0.55, 0.16, 0.05))
	for n in nozzles:
		var gst := MeshKit.begin()
		MeshKit.cone(gst, nr * 0.72, nr * 0.30, -0.5, 0.5, Vector3.ZERO, 12, true)
		var gmi := MeshKit.mi(MeshKit.finish(gst, glow_mat), "Burner")
		gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var host: Node3D = root
		if vector_nozzles:
			for pv in out["nozzles"]:
				if (pv as Node3D).position.is_equal_approx(n):
					host = pv
					break
		gmi.position = Vector3.ZERO if host != root else n
		host.add_child(gmi)
		out["burners"].append(gmi)

	# Afterburner plume. A flat additive cone just reads as a grey paper cone, so
	# this shades along the axis: white hot at the throat, through the blue
	# stoichiometric core, out to orange, with shock diamonds and an edge falloff
	# so it looks like a volume of burning gas.
	var flame_sh := Shader.new()
	flame_sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float plume_len = 4.2;
uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float flicker = 0.0;
varying float axial;
varying float radial;
void vertex() {
	axial = clamp(VERTEX.z / plume_len, 0.0, 1.0);
	radial = clamp(length(VERTEX.xy) / max(plume_len * 0.16, 0.001), 0.0, 1.0);
}
void fragment() {
	float t = axial;
	vec3 core = vec3(1.00, 0.96, 0.90);
	vec3 blue = vec3(0.42, 0.62, 1.00);
	vec3 warm = vec3(1.00, 0.46, 0.12);
	vec3 col = mix(core, blue, smoothstep(0.02, 0.22, t));
	col = mix(col, warm, smoothstep(0.45, 0.95, t));
	// shock diamonds down the first half of the plume
	float diamonds = 0.55 + 0.45 * sin(t * 34.0) * exp(-t * 5.0);
	float edge = 1.0 - smoothstep(0.35, 1.0, radial);
	float fade = (1.0 - smoothstep(0.55, 1.0, t)) * (0.35 + 0.65 * heat);
	ALBEDO = col * diamonds;
	ALPHA = edge * fade * (0.85 + flicker);
}
"""
	var flame_mat := ShaderMaterial.new()
	flame_mat.shader = flame_sh
	flame_mat.set_shader_parameter("plume_len", 4.2)
	flame_mat.set_shader_parameter("heat", 1.0)
	for n in nozzles:
		var fst := MeshKit.begin()
		MeshKit.cone(fst, nr * 0.80, 0.03, 0.0, 4.2, Vector3.ZERO, 8, false)
		var fmi := MeshKit.mi(MeshKit.finish(fst, flame_mat.duplicate()), "AB")
		fmi.position = n + Vector3(0, 0, 0.5)
		fmi.scale = Vector3(0.001, 0.001, 0.001)
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fmi)
		out["ab"].append(fmi)

	# ------------------------------------------------------------- cargo hold
	# A walkable interior carried as a child of the airframe. Occupants are
	# parented into it, so they inherit the aircraft motion exactly and never
	# fight the flight physics.
	if sh.has("hold"):
		var hd: Dictionary = sh["hold"]
		var hold := Node3D.new()
		hold.name = "Hold"
		hold.position = hd["pos"]
		hold.set_meta("half", hd["half"])          # Vector3: x, headroom, z
		var hw: Vector3 = hd["half"]
		var hold_st := MeshKit.begin()
		MeshKit.box(hold_st, Vector3(hw.x * 2.0, 0.14, hw.z * 2.0), Vector3(0, -0.07, 0))
		for sx in [-1.0, 1.0]:
			MeshKit.box(hold_st, Vector3(0.12, hw.y, hw.z * 2.0),
				Vector3(sx * hw.x, hw.y * 0.5, 0))
		MeshKit.box(hold_st, Vector3(hw.x * 2.0, hw.y, 0.14), Vector3(0, hw.y * 0.5, -hw.z))
		var ribs := int(hw.z / 1.4)
		for i in range(-ribs, ribs + 1):
			MeshKit.box(hold_st, Vector3(hw.x * 2.0, 0.10, 0.10),
				Vector3(0, hw.y * 0.92, float(i) * 1.4))
		hold.add_child(MeshKit.mi(MeshKit.finish(hold_st,
			MeshKit.mat(Color(0.30, 0.31, 0.30), 0.9, 0.1)), "Shell"))
		# crates bolted to the floor: part of the hold, so they never drift
		var crate_st := MeshKit.begin()
		for c in hd.get("crates", []):
			MeshKit.box(crate_st, c[1], c[0])
		hold.add_child(MeshKit.mi(MeshKit.finish(crate_st,
			MeshKit.mat(Color(0.34, 0.32, 0.24), 0.95, 0.0)), "Cargo"))
		# rear ramp
		var ramp := Node3D.new()
		ramp.name = "Ramp"
		ramp.position = Vector3(0, 0, hw.z)
		var rst := MeshKit.begin()
		MeshKit.box(rst, Vector3(hw.x * 1.7, 0.14, hw.z * 0.62),
			Vector3(0, -0.07, hw.z * 0.31))
		ramp.add_child(MeshKit.mi(MeshKit.finish(rst,
			MeshKit.mat(Color(0.27, 0.28, 0.27), 0.9, 0.1)), "RampDeck"))
		hold.add_child(ramp)
		root.add_child(hold)
		out["hold"] = hold
		out["ramp"] = ramp

	# ---------------------------------------------------------------- podded fans
	for pod in sh.get("pods", []):
		for pside in [1.0, -1.0]:
			var pp: Vector3 = pod["pos"]
			pp = Vector3(pp.x * pside, pp.y, pp.z)
			var pr: float = pod["r"]
			var pl: float = pod["len"]
			var pst := MeshKit.begin()
			MeshKit.cone(pst, pr * 0.86, pr, -pl * 0.5, -pl * 0.18, pp, 12, false)
			MeshKit.cone(pst, pr, pr * 0.90, -pl * 0.18, pl * 0.5, pp, 12, false)
			MeshKit.box(pst, Vector3(0.22, 1.05, pl * 0.34), pp + Vector3(0, pr * 0.8, -pl * 0.1))
			root.add_child(MeshKit.mi(MeshKit.finish(pst, mat_paint), "Nacelle"))
			var fst2 := MeshKit.begin()
			MeshKit.cone(fst2, pr * 0.80, pr * 0.20, -pl * 0.42, -pl * 0.18, pp, 12, true)
			root.add_child(MeshKit.mi(MeshKit.finish(fst2, mat_dark), "FanFace"))

	# ------------------------------------------------------- side firing battery
	# Barrels run out through the port side of the belly, the way a gunship
	# actually carries them, rather than hanging off pylons.
	var sg: Array = sh.get("side_guns", [])
	if not sg.is_empty():
		var gst := MeshKit.begin()
		for g in sg:
			var at: Vector3 = g["pos"]
			var dep := deg_to_rad(float(g.get("depress", 10.0)))
			var out_dir := Vector3(-cos(dep), -sin(dep), 0.0)
			var barrel: float = g["length"]
			var rad: float = g["radius"]
			# sponson blister where the mount passes through the skin
			MeshKit.box(gst, Vector3(0.55, rad * 4.0, rad * 7.0), at + Vector3(0.10, 0, 0))
			# trunnion and barrel, built along the outboard axis
			var seg := 9
			for i in seg:
				var t0 := float(i) / float(seg)
				var t1 := float(i + 1) / float(seg)
				var r0: float = lerpf(rad * 1.55, rad, t0)
				var r1: float = lerpf(rad * 1.55, rad, t1)
				var a := at + out_dir * (barrel * t0)
				var b := at + out_dir * (barrel * t1)
				var ring_a := MeshKit.ring(r0, r0, 0.0, 0.0, 2.0, 8)
				var ring_b := MeshKit.ring(r1, r1, 0.0, 0.0, 2.0, 8)
				var fa := PackedVector3Array()
				var fb := PackedVector3Array()
				for k in ring_a.size():
					fa.append(a + Vector3(0, ring_a[k].y, ring_a[k].x))
					fb.append(b + Vector3(0, ring_b[k].y, ring_b[k].x))
				MeshKit.loft(gst, [fa, fb], (a + b) * 0.5, false, false)
			# muzzle brake on the big one
			if rad > 0.09:
				var tip := at + out_dir * barrel
				MeshKit.box(gst, Vector3(0.34, rad * 3.0, rad * 3.0), tip)
			# recoil housing inboard
			MeshKit.box(gst, Vector3(rad * 8.0, rad * 4.0, rad * 4.0),
				at + Vector3(rad * 5.0, 0, 0))
		root.add_child(MeshKit.mi(MeshKit.finish(gst, mat_dark), "SideGuns"))

	# ------------------------------------------------------------------ rotors
	for ro in sh.get("rotors", []):
		var hub := Node3D.new()
		hub.name = "Rotor"
		hub.position = ro["pos"]
		if ro.get("axis", "y") == "x":
			hub.rotation = Vector3(0, 0, deg_to_rad(90.0))     # tail rotor
		else:
			hub.rotation = Vector3(deg_to_rad(-float(ro.get("tilt", 0.0))), 0, 0)
		var rr: float = ro["radius"]
		var blades: int = int(ro.get("blades", 4))
		var bst := MeshKit.begin()
		MeshKit.cone(bst, 0.30, 0.22, -0.30, 0.30, Vector3.ZERO, 8)
		for bnum in blades:
			var ang := TAU * float(bnum) / float(blades)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var blade := PackedVector2Array([Vector2(0.30, -0.02), Vector2(rr, -0.02),
				Vector2(rr, 0.02), Vector2(0.30, 0.02)])
			MeshKit.prism(bst, blade, dir, Vector3(0, 1, 0), dir.cross(Vector3(0, 1, 0)).normalized(),
				PackedFloat32Array([float(ro.get("chord", 0.36)), float(ro.get("chord", 0.36)) * 0.8,
					float(ro.get("chord", 0.36)) * 0.8, float(ro.get("chord", 0.36))]))
		hub.add_child(MeshKit.mi(MeshKit.finish(bst, mat_dark), "Blades"))
		# translucent disc so it reads as a spinning rotor at speed
		var dst := MeshKit.begin()
		var ring := MeshKit.ring(rr, rr, 0.0, 0.0, 2.0, 24)
		var flat := PackedVector3Array()
		for pt in ring:
			flat.append(Vector3(pt.x, 0.0, pt.y))
		MeshKit.face(dst, flat, Vector3(0, -1.0, 0))
		var dmat := MeshKit.mat(Color(0.10, 0.10, 0.11, 0.18), 0.9, 0.0)
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var disc := MeshKit.mi(MeshKit.finish(dst, dmat), "Disc")
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hub.add_child(disc)
		root.add_child(hub)
		out["rotors"].append({"node": hub, "rate": float(ro.get("rate", 28.0)), "disc": disc})

	# ---------------------------------------------------------------- propellers
	for pr in sh.get("props", []):
		var sides: Array = [1.0, -1.0] if absf((pr["pos"] as Vector3).x) > 0.01 else [1.0]
		for pside in sides:
			var ppos: Vector3 = pr["pos"]
			ppos = Vector3(ppos.x * pside, ppos.y, ppos.z)
			var nac := MeshKit.begin()
			MeshKit.cone(nac, 0.95, 0.55, -2.6, 2.4, ppos, 10)
			root.add_child(MeshKit.mi(MeshKit.finish(nac, mat_paint), "Nacelle"))
			var hub := Node3D.new()
			hub.name = "Prop"
			hub.position = ppos + Vector3(0, 0, -2.8)
			var bst := MeshKit.begin()
			var pr_r: float = pr["r"]
			for bnum in 4:
				var ang := TAU * float(bnum) / 4.0
				var dir := Vector3(cos(ang), sin(ang), 0.0)
				var blade := PackedVector2Array([Vector2(0.30, -0.28), Vector2(pr_r, -0.14),
					Vector2(pr_r, 0.14), Vector2(0.30, 0.30)])
				MeshKit.prism(bst, blade, dir, Vector3(0, 0, 1),
					dir.cross(Vector3(0, 0, 1)).normalized(),
					PackedFloat32Array([0.07, 0.03, 0.03, 0.07]))
			MeshKit.cone(bst, 0.34, 0.16, -0.5, 0.3, Vector3.ZERO, 8)
			hub.add_child(MeshKit.mi(MeshKit.finish(bst, mat_dark), "Blades"))
			root.add_child(hub)
			out["props"].append(hub)

	# ------------------------------------------------------------------ canards
	if sh.has("canard"):
		var cn: Dictionary = sh["canard"]
		var cpoly: Array = cn["poly"]
		var c_xr := 1e9
		var c_zmin := 1e9
		var c_zmax := -1e9
		for pt in cpoly:
			c_xr = minf(c_xr, pt.x)
			c_zmin = minf(c_zmin, pt.y)
			c_zmax = maxf(c_zmax, pt.y)
		var c_hinge := lerpf(c_zmin, c_zmax, 0.40)
		for cside in [1.0, -1.0]:
			var pivot := Node3D.new()
			pivot.name = "Canard" + ("R" if cside > 0 else "L")
			pivot.position = Vector3(c_xr * cside, cn["y"], c_hinge)
			var cnst := MeshKit.begin()
			_add_planform(cnst, cn, cside, Vector3(-c_xr * cside, -cn["y"], -c_hinge))
			pivot.add_child(MeshKit.mi(MeshKit.finish(cnst, mat_paint), "Mesh"))
			root.add_child(pivot)
			out["canards"].append(pivot)
			out["parts"]["canard_" + ("r" if cside > 0 else "l")] = pivot

	# ---------------------------------------------------------------- stabilators
	var stb: Dictionary = sh["stab"]
	var poly: Array = stb["poly"]
	var zmin := 1e9
	var zmax := -1e9
	var xr := 1e9
	for p in poly:
		zmin = minf(zmin, p.y)
		zmax = maxf(zmax, p.y)
		xr = minf(xr, p.x)
	var hinge_z := lerpf(zmin, zmax, 0.42)
	for side in [1.0, -1.0]:
		var pivot := Node3D.new()
		pivot.name = "Stab" + ("R" if side > 0 else "L")
		pivot.position = Vector3(xr * side, stb["y"], hinge_z)
		var sst := MeshKit.begin()
		_add_planform(sst, stb, side, Vector3(-xr * side, -stb["y"], -hinge_z))
		pivot.add_child(MeshKit.mi(MeshKit.finish(sst, mat_paint), "Mesh"))
		root.add_child(pivot)
		out["stabs"].append(pivot)
		out["parts"]["stab_" + ("r" if side > 0 else "l")] = pivot

	# ---------------------------------------------------------------- gear
	var mat_strut := MeshKit.mat(Color(0.62, 0.64, 0.66), 0.35, 0.85)
	var mat_tyre := MeshKit.mat(Color(0.08, 0.08, 0.09), 0.85, 0.0)
	for g in spec["gear"]:
		var p: Vector3 = g["pos"]
		var glen: float = g["len"]
		var pivot := Node3D.new()
		pivot.name = "Gear"
		# the leg hangs from the wheel well in the belly down to the axle
		pivot.position = Vector3(p.x, p.y + glen, p.z)
		var strut := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.085
		cyl.bottom_radius = 0.065
		cyl.height = glen
		cyl.radial_segments = 8
		strut.mesh = cyl
		strut.material_override = mat_strut
		strut.position = Vector3(0, -glen * 0.5, 0)
		pivot.add_child(strut)
		var wheels := 1 if g["steer"] else 1
		for w in wheels:
			var wm := MeshInstance3D.new()
			var wc := CylinderMesh.new()
			wc.top_radius = g["r"]
			wc.bottom_radius = g["r"]
			wc.height = g["r"] * 0.66
			wc.radial_segments = 12
			wm.mesh = wc
			wm.material_override = mat_tyre
			wm.rotation_degrees = Vector3(0, 0, 90)
			wm.position = Vector3(0, -glen, 0)
			pivot.add_child(wm)
			out["wheels"].append({"node": wm, "r": g["r"]})
		root.add_child(pivot)
		out["gear"].append(pivot)

	# ---------------------------------------------------------------- bays
	var mat_bay := MeshKit.mat(Color(0.09, 0.10, 0.11), 0.8, 0.1)
	for bay in spec["bays"]:
		var doors: Array[Node3D] = []
		if bay["kind"] == "internal":
			var pv: Vector3 = bay["pivot"]
			var span: float = bay["door_span"]
			var dlen: float = bay["door_len"]
			var sides: Array = [-1.0, 1.0]
			if bay.has("side"):
				sides = [float(bay["side"])]
			# recess so the open bay reads as a cavity
			var cheek: bool = bay.get("door_kind", "belly") == "cheek"
			var cav := MeshInstance3D.new()
			var cbox := BoxMesh.new()
			cav.material_override = mat_bay
			if cheek:
				cbox.size = Vector3(span * 0.5, span * 0.9, dlen * 0.92)
				cav.position = pv + Vector3(sides[0] * span * 0.18, -span * 0.42, 0)
			else:
				cbox.size = Vector3(span * (2.0 if sides.size() > 1 else 1.0) * 0.94, 0.62, dlen * 0.94)
				cav.position = pv + Vector3(0.0 if sides.size() > 1 else sides[0] * span * 0.5, 0.30, 0)
			cav.mesh = cbox
			root.add_child(cav)
			for sd in sides:
				var hinge := Node3D.new()
				hinge.name = "Door"
				hinge.position = pv + Vector3(0, 0, 0) if cheek else pv + Vector3(sd * span, 0, 0)
				var plate := MeshInstance3D.new()
				var b := BoxMesh.new()
				if cheek:
					b.size = Vector3(0.06, span, dlen)
					plate.position = Vector3(0, -span * 0.5, 0)
				else:
					b.size = Vector3(span, 0.06, dlen)
					plate.position = Vector3(-sd * span * 0.5, 0, 0)
				plate.mesh = b
				plate.material_override = MeshKit.panelled(paint.darkened(0.06), 0.45, 0.06, 0.9)
				hinge.add_child(plate)
				hinge.set_meta("side", sd)
				root.add_child(hinge)
				doors.append(hinge)
		out["doors"][bay["id"]] = doors
		# stores
		var idx := 0
		for stn in bay["stations"]:
			var holder := Node3D.new()
			holder.name = "Store"
			holder.position = stn["pos"]
			if bay["kind"] == "external" and not stn.get("tip", false):
				var pyl := MeshInstance3D.new()
				var pb := BoxMesh.new()
				pb.size = Vector3(0.16, 0.42, 1.1)
				pyl.mesh = pb
				pyl.material_override = mat_paint
				pyl.position = Vector3(0, 0.34, 0)
				holder.add_child(pyl)
			holder.visible = bay["kind"] == "external"
			var mi := MeshKit.mi(WeaponSpec.build_mesh(stn["weapon"]), "Round")
			mi.rotation_degrees = Vector3(0, 0, 0)
			holder.add_child(mi)
			root.add_child(holder)
			out["stores"][str(bay["id"], "#", idx)] = holder
			idx += 1

	# ---------------------------------------------------------------- lights
	var half_span: float = spec["span"] * 0.5
	var wing_z: float = sh["wing"]["poly"][1].y
	for l in [[-half_span, Color(1.0, 0.15, 0.15)], [half_span, Color(0.2, 1.0, 0.35)]]:
		var lm := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.09
		sp.height = 0.18
		sp.radial_segments = 6
		sp.rings = 4
		lm.mesh = sp
		lm.material_override = MeshKit.mat(Color.BLACK, 0.4, 0.0, l[1])
		lm.position = Vector3(l[0] * 0.97, sh["wing"]["y"], wing_z * 0.6)
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lm)
		out["lights"].append(lm)

	# ------------------------------------------------- cockpit furniture
	# Everything is placed relative to the eye point, because a glare shield a
	# few centimetres out of place fills the whole first-person view.
	var eye := Vector3(0.0, cp["y"] - 0.10, lerpf(cp["z0"], cp["z1"], 0.34))
	var coam := MeshKit.begin()
	MeshKit.box(coam, Vector3(1.24, 0.26, 0.66), eye + Vector3(0, -0.54, -0.78))
	MeshKit.box(coam, Vector3(1.06, 0.34, 0.10), eye + Vector3(0, -0.66, -1.09))
	for sx in [-1.0, 1.0]:
		MeshKit.box(coam, Vector3(0.13, 0.34, 1.7), eye + Vector3(sx * 0.60, -0.50, -0.10))
		# windscreen bow: high enough to frame the view instead of splitting it
		MeshKit.box(coam, Vector3(0.035, 0.66, 0.04), eye + Vector3(sx * 0.53, 0.12, -1.30))
	MeshKit.box(coam, Vector3(1.10, 0.04, 0.04), eye + Vector3(0, 0.45, -1.30))
	var coam_mi := MeshKit.mi(MeshKit.finish(coam, MeshKit.mat(Color(0.085, 0.09, 0.095), 0.92, 0.0)), "Coaming")
	coam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(coam_mi)
	out["cockpit_parts"].append(coam_mi)

	# ---- cockpit tub and seat -------------------------------------------
	# The trough cut into the spine above needs a floor and walls, or you see
	# straight through the aeroplane; and the pilot needs something to sit in.
	var tub := MeshKit.begin()
	var floor_y: float = cp["y"] - 0.62
	var tz0: float = minf(cp["z0"], cp["z1"]) - 0.4
	var tz1: float = maxf(cp["z0"], cp["z1"]) + 0.2
	var tlen: float = tz1 - tz0
	var tmid: float = (tz0 + tz1) * 0.5
	# Floor, low side sills and a rear bulkhead only. The first version boxed the
	# well in on all four sides at head height, which looked like a cockpit from
	# outside and like the inside of a crate from the seat: the forward wall sat
	# straight across the view. The coaming ahead of the pilot already closes
	# the front off.
	MeshKit.box(tub, Vector3(1.12, 0.05, tlen), Vector3(0, floor_y, tmid))
	for sx in [-1.0, 1.0]:
		MeshKit.box(tub, Vector3(0.06, 0.34, tlen), Vector3(sx * 0.56, floor_y + 0.17, tmid))
	MeshKit.box(tub, Vector3(1.12, 0.60, 0.06), Vector3(0, floor_y + 0.30, tz1))
	var tub_mi := MeshKit.mi(MeshKit.finish(tub,
		MeshKit.mat(Color(0.055, 0.06, 0.065), 0.95, 0.0)), "CockpitTub")
	tub_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tub_mi)
	out["cockpit_parts"].append(tub_mi)

	# ejection seat: pan, back, headbox
	var seat := MeshKit.begin()
	var seat_z: float = lerpf(cp["z0"], cp["z1"], 0.62)
	MeshKit.box(seat, Vector3(0.52, 0.09, 0.52), Vector3(0, floor_y + 0.20, seat_z))
	MeshKit.box(seat, Vector3(0.52, 0.72, 0.10), Vector3(0, floor_y + 0.56, seat_z + 0.28))
	MeshKit.box(seat, Vector3(0.40, 0.24, 0.14), Vector3(0, floor_y + 0.98, seat_z + 0.26))
	for sx in [-1.0, 1.0]:
		MeshKit.box(seat, Vector3(0.07, 0.50, 0.30), Vector3(sx * 0.26, floor_y + 0.50, seat_z + 0.10))
	var seat_mi := MeshKit.mi(MeshKit.finish(seat,
		MeshKit.mat(Color(0.10, 0.11, 0.12), 0.85, 0.0)), "Seat")
	seat_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(seat_mi)
	out["cockpit_parts"].append(seat_mi)
	# where a seated figure's backside goes, which is not where the eye goes
	out["seat"] = Vector3(0, floor_y + 0.25, seat_z - 0.04)

	# instrument glow strip so the dash is not a black void at night-ish angles
	var dash := MeshKit.begin()
	MeshKit.box(dash, Vector3(0.62, 0.02, 0.13), eye + Vector3(0, -0.42, -1.02))
	var dash_mi := MeshKit.mi(MeshKit.finish(dash,
		MeshKit.mat(Color(0.03, 0.05, 0.05), 0.6, 0.0, Color(0.03, 0.13, 0.09))), "Dash")
	dash_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dash_mi)
	out["cockpit_parts"].append(dash_mi)

	# tailhook, stowed under the aft fuselage
	var tail_z: float = sections[sections.size() - 1][0] - 1.2
	var hook := Node3D.new()
	hook.name = "HookPivot"
	hook.position = Vector3(0, sections[sections.size() - 1][3] - 0.45, tail_z - 1.6)
	var hst := MeshKit.begin()
	MeshKit.box(hst, Vector3(0.13, 0.13, 2.5), Vector3(0, 0, 1.25))
	MeshKit.box(hst, Vector3(0.42, 0.26, 0.34), Vector3(0, -0.06, 2.5))
	hook.add_child(MeshKit.mi(MeshKit.finish(hst, MeshKit.mat(Color(0.16, 0.16, 0.17), 0.7, 0.4)), "Hook"))
	root.add_child(hook)
	out["hook"] = hook
	out["hook_tip"] = hook.position + Vector3(0, 0, 2.5)

	out["tips"] = [Vector3(half_span * 0.94, sh["wing"]["y"], wing_z * 0.75),
		Vector3(-half_span * 0.94, sh["wing"]["y"], wing_z * 0.75)]
	out["cockpit"] = Vector3(0.0, cp["y"] - 0.10, lerpf(cp["z0"], cp["z1"], 0.34))
	return out

## Sink a trough into the top of the fuselage so the crew sit IN the aeroplane
## instead of on top of the skin. The upper vertices of every station inside the
## cockpit are pulled down to the sill, fading in and out along the length so it
## reads as a well with a coaming rather than a slot chopped through the spine.
static func _cut_cockpit(rings: Array, z_a: float, z_b: float, sill: float) -> void:
	var span: float = maxf(z_b - z_a, 0.001)
	for r in rings.size():
		var ring: PackedVector3Array = rings[r]
		if ring.is_empty():
			continue
		var z: float = ring[0].z
		if z < z_a or z > z_b:
			continue
		var u: float = clampf((z - z_a) / span, 0.0, 1.0)
		var depth: float = sin(u * PI)             # nothing at the ends, full in the middle
		for i in ring.size():
			var p: Vector3 = ring[i]
			var t: float = TAU * float(i) / float(ring.size())
			# only the upper surface, and only the middle of it: the sides stay
			# where they are so there is still a rail to sit behind
			var top_amt: float = clampf((sin(t) - 0.30) / 0.70, 0.0, 1.0)
			if top_amt <= 0.0:
				continue
			p.y = lerpf(p.y, minf(p.y, sill), top_amt * depth)
			ring[i] = p
		rings[r] = ring

## One engine inlet. The duct is lofted from a raked lip back into the fuselage
## so it reads as an opening with depth, with a splitter plate holding it off the
## skin the way a real supersonic inlet does.
static func _add_intake(st: SurfaceTool, at: Vector3, size: Vector3, yaw: float,
		side: float, style: String) -> void:
	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	var length: float = size.z
	# lip is raked back at the top on a caret inlet, straight on a chin inlet
	var rake: float = 0.55 if style == "caret" else 0.18
	var rings: Array = []
	var steps := 5
	for i in steps + 1:
		var t := float(i) / float(steps)
		# lip -> throat -> merge into the skin
		var w: float = lerpf(hw, hw * 0.62, t)
		var h: float = lerpf(hh, hh * 0.72, t)
		var power: float = lerpf(1.45 if style == "caret" else 2.6, 3.2, t)
		var z: float = -length * 0.5 + length * t
		var ring := MeshKit.ring(w, h, 0.0, 0.0, power, 10)
		var out := PackedVector3Array()
		for pt in ring:
			# rake the lip: the outboard top corner leads
			var lead: float = rake * (1.0 - t) * (pt.y / maxf(h, 0.01)) * hh
			var lx: float = pt.x
			var ly: float = pt.y
			var lz: float = z + lead
			# yaw the whole duct outboard
			var rx: float = lx * cos(yaw) - lz * sin(yaw)
			var rz: float = lx * sin(yaw) + lz * cos(yaw)
			out.append(at + Vector3(rx, ly, rz))
		rings.append(out)
	MeshKit.loft(st, rings, at, false, false)
	# inlet face: a dark recessed cap just inside the lip
	var cap: PackedVector3Array = rings[0]
	var sunk := PackedVector3Array()
	for pt in cap:
		sunk.append(pt + Vector3(sin(yaw), 0, cos(yaw)) * (length * 0.30))
	MeshKit.loft(st, [cap, sunk], at, false, true)
	# boundary layer splitter between the duct and the fuselage
	var sp := PackedVector2Array([
		Vector2(-length * 0.48, -hh * 0.9), Vector2(length * 0.35, -hh * 0.75),
		Vector2(length * 0.35, hh * 0.85), Vector2(-length * 0.42, hh * 0.95)])
	MeshKit.prism(st, sp, Vector3(sin(yaw), 0, cos(yaw)), Vector3(0, 1, 0),
		Vector3(cos(yaw), 0, -sin(yaw)),
		PackedFloat32Array([0.05, 0.05, 0.05, 0.05]),
		at - Vector3(side * hw * 0.98, 0, 0))

# ---------------------------------------------------------------------------
## Build a control surface as its own node hinged about `axis`. `poly` are the
## surface corners in aircraft space; `n` is the surface normal (thickness
## direction). Deflection is a rotation about the node's local Y.
static func _hinged(poly: PackedVector3Array, p0: Vector3, axis: Vector3, n: Vector3,
		thick: float, mat: Material, nm: String) -> Node3D:
	var node := Node3D.new()
	node.name = nm
	var zdir := axis.cross(n).normalized()
	var xdir := axis.cross(zdir).normalized()
	node.transform = Transform3D(Basis(xdir, axis, zdir), p0)
	# Remember the rest orientation: assigning `rotation.y` later would replace the
	# whole basis with a plain Euler rotation and throw the hinge frame away.
	node.set_meta("rest", node.transform.basis)
	var flat := PackedVector2Array()
	var th := PackedFloat32Array()
	for w in poly:
		var d := w - p0
		flat.append(Vector2(d.dot(axis), d.dot(zdir)))
		th.append(thick * 0.5)
	var st := MeshKit.begin()
	MeshKit.prism(st, flat, Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), th)
	node.add_child(MeshKit.mi(MeshKit.finish(st, mat), "Mesh"))
	return node

static func _add_planform(st: SurfaceTool, w: Dictionary, side: float, off := Vector3.ZERO) -> void:
	var poly := PackedVector2Array()
	var raw: Array = w["poly"]
	var xmax := 0.0
	for p in raw:
		xmax = maxf(xmax, p.x)
	var xmin := 1e9
	for p in raw:
		xmin = minf(xmin, p.x)
	var thick := PackedFloat32Array()
	for i in raw.size():
		var p: Vector2 = raw[i]
		poly.append(p)
		var t := inverse_lerp(xmin, maxf(xmax, xmin + 0.01), p.x)
		thick.append(lerpf(w["t_root"], w["t_tip"], clampf(t, 0.0, 1.0)))
	MeshKit.prism(st, poly, Vector3(side, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
		thick, off + Vector3(0, w["y"], 0))

static func _add_fin(st: SurfaceTool, f: Dictionary, side: float) -> void:
	var raw: Array = f["poly"]
	var poly := PackedVector2Array()
	for p in raw:
		poly.append(p)
	var thick := PackedFloat32Array()
	var ymax := 0.0
	for p in raw:
		ymax = maxf(ymax, absf(p.y))
	for p in raw:
		thick.append(lerpf(f["t"], f["t"] * 0.42, clampf(absf(p.y) / maxf(ymax, 0.01), 0.0, 1.0)))
	var cant := deg_to_rad(f["cant"]) * side
	# poly is (z, height): up axis is tilted outboard by the cant angle
	var up := Vector3(sin(cant), cos(cant), 0.0)
	var fwd := Vector3(0, 0, 1)
	MeshKit.prism(st, poly, fwd, up, up.cross(fwd).normalized(), thick,
		Vector3(f["x"] * side, 0, 0))
