class_name Aircraft
extends RigidBody3D
## Rigid-body flight model shared by the player and the AI. Aerodynamics run in
## _integrate_forces; gear, bays and stores are simulated on top of it.

signal store_released(node)
signal touched_down(info)
signal died(who)

const RHO0 := 1.225
const Q_REF := 38000.0          # dynamic pressure where control power is 100 %

var spec: Dictionary
var pilot_name := "Viper 1"
var team := 0                    # 0 = player side, 1 = hostile

# ---- control inputs (set by _pilot) --------------------------------------
var in_pitch := 0.0
var in_roll := 0.0
var in_yaw := 0.0
var throttle := 0.0
var wheel_brake := false
var airbrake := false
var flaps := 0.0
var assist := true

# ---- state ---------------------------------------------------------------
var power := 0.0                 # spooled engine setting 0..1
var fuel := 0.0
var ammo := 0
var health := 100.0
var alive := true
var gear_down := true
var gear_anim := 1.0             # 0 up, 1 down
var flap_anim := 0.0
var bays := {}                   # id -> {open, anim, drag, kind}
var stores := []                 # {bay, idx, weapon, node, gone}
var selected := 0                # index into weapon_types
var weapon_types: Array = []
var gun_cd := 0.0
var fire_cd := 0.0
var target: Node3D = null
var lock_time := 0.0
var locked := false
var designated := Vector3.INF    # laser spot from the pod, world space
var designated_node: Node3D = null  # and the thing it is on, when point tracking
var missile_warn := 0.0

# ---- telemetry -----------------------------------------------------------
var aoa := 0.0
var beta := 0.0
var g_load := 1.0
var mach := 0.0
var ias := 0.0
var agl := 0.0
var on_ground := true
var vspeed := 0.0
var stalling := false
var last_touchdown := {}
var _was_airborne := false
var _model := {}
var _stab_l: Node3D
var _stab_r: Node3D
var _ab: Array = []
var _gear_nodes: Array = []
var _flaps: Array = []
var _ailerons: Array = []
var _rudders: Array = []
var _wheels: Array = []
var _canards: Array = []
var _props: Array = []
var _burners: Array = []
var _rotors: Array = []
var _rotor_spin := 0.0
var _prop_spin := 0.0
var _wheel_spin := 0.0
var _vortex: Array = []
var _shock: MeshInstance3D
var _shock_shader: ShaderMaterial
var _streaks: GPUParticles3D
var air_anim := 0.0
var canopy_open := false
var canopy_anim := 0.0
var lost := {}                   # part id -> true once it has been shot off
var wrecked := false
var ghost := false               # replicated remote aircraft: no local physics
var hover_cmd := false           # STOVL: pilot has asked for the jet to swivel
var jetborne := 0.0              # 0 wingborne, 1 hanging on the nozzle
var nozzle_pitch := 0.0          # nozzle deflection, radians, +ve nose up demand
var nozzle_yaw := 0.0
var _nozzle_arm := Vector3.ZERO  # mean nozzle position in body coordinates
var _nozzles: Array = []         # pivots, on vectoring aircraft only
var bounds := AABB()             # local model extents, for hull_distance()
var _pen_lift := 1.0
var g_strain := 0.0              # 0 clear sight, 1 blacked out
var g_red := 0.0                 # negative-g redout, same scale
var g_peak := 0.0                # highest +Gz this sortie
var g_min := 0.0                 # and the lowest
var _pr_i := 0.0                 # fly-by-wire pitch rate integrator
var _rr_i := 0.0                 # and roll
var _pen_roll_bias := 0.0
var _pen_pitch := 1.0
var _pen_yaw := 1.0
var _pen_drag := 0.0
var _pen_roll_auth := 1.0
var _wreck_t := 0.0
var _life_t := 0.0
var _overspeed_warn := 0.0
var _pending_fire := false
var ramp_open := false
var ramp_anim := 0.0
var hook_down := false
var hook_anim := 0.0
var trapped := false
var _trap_t := 0.0
var _prev_hook_z := 0.0
var _burn := 0.0
var _rcs := 1.0
var flares := 60
var _flare_t := 0.0
var _flare_cd := 0.0
var debug_forces := false
var _dbg_lift := 0.0
var _dbg_drag := 0.0
var _dbg_gear := Vector3.ZERO
var _dbg_gear_fwd := 0.0
var surf_pitch := 0.0
var surf_roll := 0.0
var surf_yaw := 0.0
# low-pass copies used only for the animation, so a busy control loop does not
# make the surfaces strobe
var _vis_pitch := 0.0
var _vis_roll := 0.0
var _vis_yaw := 0.0

# --------------------------------------------------------------------------
## Turn this aircraft into a kinematic stand-in driven by network state.
func make_ghost() -> void:
	ghost = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	gravity_scale = 0.0
	set_meta("ghost", true)

func setup(id: String) -> void:
	spec = JetSpec.get_spec(id)
	_model = JetFactory.build(spec)
	add_child(_model["root"])
	_stab_r = _model["stabs"][0]
	_stab_l = _model["stabs"][1]
	_ab = _model["ab"]
	_nozzles = _model.get("nozzles", [])
	_gear_nodes = _model["gear"]
	_flaps = _model["flaps"]
	_ailerons = _model["ailerons"]
	_rudders = _model["rudders"]
	_wheels = _model["wheels"]
	_canards = _model.get("canards", [])
	_props = _model.get("props", [])
	_burners = _model.get("burners", [])
	_rotors = _model.get("rotors", [])
	_build_aero_fx()

	mass = spec["mass"]
	inertia = spec["inertia"]
	fuel = spec["fuel"]
	ammo = spec["gun"]["rounds"]
	can_sleep = false
	continuous_cd = true
	# The project default damping would otherwise be *added* to ours and quietly
	# eat energy; this model supplies all of its own damping aerodynamically.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	gravity_scale = 1.0
	max_contacts_reported = 0
	collision_layer = 0
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var cap := BoxShape3D.new()
	cap.size = Vector3(spec["span"] * 0.6, 2.2, 12.0)
	shape.shape = cap
	add_child(shape)

	for bay in spec["bays"]:
		bays[bay["id"]] = {
			"open": bay["kind"] == "external",
			"anim": 1.0 if bay["kind"] == "external" else 0.0,
			"drag": bay.get("drag", 0.0),
			"kind": bay["kind"],
			"time": maxf(bay.get("open_time", 1.0), 0.01),
		}
		var i := 0
		for stn in bay["stations"]:
			stores.append({
				"bay": bay["id"], "idx": i, "weapon": stn["weapon"],
				"node": _model["stores"][str(bay["id"], "#", i)], "gone": false,
			})
			i += 1
	weapon_types = ["gun"]
	for s in stores:
		if not weapon_types.has(s["weapon"]):
			weapon_types.append(s["weapon"])
	selected = 1 if weapon_types.size() > 1 else 0
	if spec.get("gunship", false):
		# a gunship's battery replaces the nose gun in the selection list, and
		# this has to happen after the generic list is built or it is overwritten
		weapon_types = []
		for g in spec["guns"]:
			weapon_types.append(String(g["id"]))
		for st2 in stores:
			if not weapon_types.has(st2["weapon"]):
				weapon_types.append(st2["weapon"])
		selected = 0
	_cache_bounds()
	var nz: Array = spec["shape"]["nozzles"]
	if not nz.is_empty():
		var sum := Vector3.ZERO
		for n in nz:
			sum += n as Vector3
		_nozzle_arm = sum / float(nz.size())
	_refresh_mass()

## Local half extents of the whole model, used to work out how close somebody on
## foot actually is to the machine rather than to the point it is measured from.
func _cache_bounds() -> void:
	var box := AABB()
	var first := true
	for c in find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var ab: AABB = mi.get_aabb()
		var xf: Transform3D = global_transform.affine_inverse() * mi.global_transform \
			if is_inside_tree() else mi.transform
		var t := xf * ab
		box = t if first else box.merge(t)
		first = false
	bounds = box

## Distance from a world point to this machine's hull, not to its origin. A
## transport measured from the centre reads as fifteen metres away while you are
## standing under the wing.
func hull_distance(p: Vector3) -> float:
	var lp: Vector3 = global_transform.affine_inverse() * p
	var mn := bounds.position
	var mx := bounds.end
	var q := Vector3(clampf(lp.x, mn.x, mx.x), clampf(lp.y, mn.y, mx.y),
		clampf(lp.z, mn.z, mx.z))
	return lp.distance_to(q)

func _refresh_mass() -> void:
	var m: float = spec["mass"] + fuel
	for s in stores:
		if not s["gone"]:
			m += WeaponSpec.get_spec(s["weapon"])["mass"]
	mass = m

func has_hold() -> bool:
	return _model.has("hold")

func hold_node() -> Node3D:
	return _model.get("hold")

func toggle_ramp() -> void:
	ramp_open = not ramp_open

func toggle_hook() -> void:
	hook_down = not hook_down

## World position of the hook point, used for the arrestor wires.
func hook_tip() -> Vector3:
	var local: Vector3 = _model.get("hook_tip", Vector3(0, -1.0, 6.0))
	var drop := Vector3(0, -sin(deg_to_rad(52.0)) * 2.5 * hook_anim, -0.6 * hook_anim)
	return global_transform * (local + drop)

func has_canopy() -> bool:
	return _model.has("canopy")

func set_canopy(open: bool, instant := false) -> void:
	if not has_canopy():
		canopy_open = false
		canopy_anim = 0.0
		return
	canopy_open = open
	if instant:
		canopy_anim = 1.0 if open else 0.0
		_animate(0.0)

func ladder_offset() -> Vector3:
	return _model.get("ladder_pos", Vector3(-1.6, 0, -4.0))

## Where a seated figure's hips belong, in body coordinates.
func seat_offset() -> Vector3:
	return _model.get("seat", cockpit_offset() + Vector3(0, -0.55, 0.12))

func cockpit_offset() -> Vector3:
	return _model.get("cockpit", Vector3(0, 1.0, -2.0))

# --------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if ghost:
		# remote aircraft still animate their moving parts, they just do not fly
		_animate(delta)
		return
	if wrecked:
		_wreck_t += delta
		var g := Sim.height_at(global_position.x, global_position.z)
		if global_position.y - g < 3.0 or _wreck_t > 24.0:
			Effects.explosion(get_tree().current_scene, global_position, 26.0)
			queue_free()
		return
	if not alive:
		return
	_life_t += delta
	_pilot(delta)
	_animate(delta)
	# a shot held up by the doors goes as soon as they are open
	if _pending_fire and alive:
		var w := current_weapon()
		if w == "gun":
			_pending_fire = false
		else:
			var st := next_store(w)
			if st.is_empty():
				_pending_fire = false
			elif bays[st["bay"]]["anim"] >= 0.96:
				fire()
	_flare_t = maxf(_flare_t - delta, 0.0)
	_flare_cd = maxf(_flare_cd - delta, 0.0)
	gun_cd = maxf(gun_cd - delta, 0.0)
	fire_cd = maxf(fire_cd - delta, 0.0)
	missile_warn = maxf(missile_warn - delta, 0.0)
	_update_lock(delta)

## Override in subclasses to drive the stick.
func _pilot(_delta: float) -> void:
	pass

func _animate(delta: float) -> void:
	# The cans follow the vector. A nose up demand deflects the exhaust upward,
	# which is the opposite way from the force it puts on the airframe, so the
	# pitch sign is negated here.
	for i in _nozzles.size():
		var pv := _nozzles[i] as Node3D
		if is_instance_valid(pv):
			pv.rotation = Vector3(-nozzle_pitch, nozzle_yaw, 0.0)
	ramp_anim = move_toward(ramp_anim, 1.0 if ramp_open else 0.0, delta / 3.0)
	if _model.has("ramp"):
		(_model["ramp"] as Node3D).rotation.x = deg_to_rad(22.0) * ramp_anim
	hook_anim = move_toward(hook_anim, 1.0 if hook_down else 0.0, delta / 1.4)
	if _model.has("hook"):
		(_model["hook"] as Node3D).rotation.x = deg_to_rad(-52.0) * hook_anim
	canopy_anim = move_toward(canopy_anim, 1.0 if canopy_open else 0.0, delta / 2.6)
	if _model.has("canopy"):
		(_model["canopy"] as Node3D).rotation.x = deg_to_rad(34.0) * canopy_anim
	if _model.has("ladder"):
		(_model["ladder"] as Node3D).visible = canopy_anim > 0.02
	var target_gear := 1.0 if gear_down else 0.0
	gear_anim = move_toward(gear_anim, target_gear, delta / 2.4)
	flap_anim = move_toward(flap_anim, flaps, delta / 1.6)
	for g in _gear_nodes:
		g.rotation.x = deg_to_rad(88.0) * (1.0 - gear_anim)
		g.visible = gear_anim > 0.01
	for id in bays:
		var b: Dictionary = bays[id]
		if b["kind"] == "external":
			continue
		b["anim"] = move_toward(b["anim"], 1.0 if b["open"] else 0.0, delta / b["time"])
		var doors: Array = _model["doors"].get(id, [])
		var ang: float = 0.0
		for bay in spec["bays"]:
			if bay["id"] == id:
				ang = deg_to_rad(bay["door_angle"])
		for d in doors:
			d.rotation.z = ang * b["anim"] * float(d.get_meta("side"))
		for s in stores:
			if s["bay"] == id:
				s["node"].visible = not s["gone"] and b["anim"] > 0.04
	# control surfaces follow the fly-by-wire outputs, not the raw stick, so you
	# can see the jet trimming itself
	var lp: float = clampf(delta * 7.0, 0.0, 1.0)
	_vis_pitch = lerpf(_vis_pitch, surf_pitch, lp)
	_vis_roll = lerpf(_vis_roll, surf_roll, lp)
	_vis_yaw = lerpf(_vis_yaw, surf_yaw, lp)
	var sd := deg_to_rad(17.0)
	if is_instance_valid(_stab_r):
		_stab_r.rotation.x = sd * clampf(_vis_pitch + _vis_roll * 0.45, -1.0, 1.0)
	if is_instance_valid(_stab_l):
		_stab_l.rotation.x = sd * clampf(_vis_pitch - _vis_roll * 0.45, -1.0, 1.0)
	if not _rotors.is_empty():
		_rotor_spin += delta * (6.0 + power * 26.0)
		for r in _rotors:
			var rn: Node3D = r["node"]
			if is_instance_valid(rn):
				rn.rotate_y(delta * float(r["rate"]) * (0.25 + power * 0.85))
			var dsc: MeshInstance3D = r["disc"]
			if is_instance_valid(dsc):
				dsc.visible = power > 0.35
	_prop_spin += delta * (14.0 + power * 42.0)
	for pnode in _props:
		if is_instance_valid(pnode):
			(pnode as Node3D).rotation.z = _prop_spin
	for cnd in _canards:
		if is_instance_valid(cnd):
			cnd.rotation.x = deg_to_rad(-14.0) * _vis_pitch
	var fd := deg_to_rad(34.0) * flap_anim
	for f in _flaps:
		_deflect(f, fd)
	for a in _ailerons:
		_deflect(a["node"], fd * 0.35 - deg_to_rad(21.0) * _vis_roll * float(a["side"]))
	# split rudders double as the speedbrake: trailing edges swing inboard
	air_anim = move_toward(air_anim, 1.0 if airbrake else 0.0, delta / 0.8)
	for r in _rudders:
		var side := float(r.get_meta("side", 1.0))
		_deflect(r, deg_to_rad(23.0) * _vis_yaw - side * deg_to_rad(30.0) * air_anim)
	_update_aero_fx()
	# wheels spin up with ground speed and keep turning after lift-off
	var gs := linear_velocity.dot(-global_transform.basis.z)
	for w in _wheels:
		var wr: float = w["r"]
		_wheel_spin += (gs / maxf(wr, 0.1)) * delta if on_ground else 0.0
		break
	if not on_ground:
		_wheel_spin += 0.0
	for w in _wheels:
		var n: Node3D = w["node"]
		n.transform.basis = Basis(Vector3(1, 0, 0), _wheel_spin) * Basis(Vector3(0, 0, 1), PI * 0.5)
	for bn in _burners:
		var bm: MeshInstance3D = bn
		if is_instance_valid(bm) and bm.mesh.get_surface_count() > 0:
			var mm: StandardMaterial3D = bm.mesh.surface_get_material(0)
			if mm:
				mm.emission_energy_multiplier = 0.6 + power * 6.5
	# afterburner plume
	var ab_t: float = clampf((power - 0.78) / 0.22, 0.0, 1.0)
	var core: float = clampf(power * 1.1, 0.0, 1.0)
	for f in _ab:
		var fm: ShaderMaterial = (f as MeshInstance3D).mesh.surface_get_material(0)
		if fm:
			fm.set_shader_parameter("heat", 0.25 + 0.75 * ab_t)
			fm.set_shader_parameter("flicker", randf_range(-0.10, 0.10) * (0.3 + ab_t))
		var s: float = 0.25 * core + 0.9 * ab_t
		var flick := 1.0 + randf_range(-0.08, 0.08) * (1.0 if s > 0.01 else 0.0)
		f.scale = Vector3(maxf(0.05, 0.35 + 0.65 * ab_t), maxf(0.05, 0.35 + 0.65 * ab_t),
			maxf(0.001, s * flick))
		f.visible = s > 0.02

# --------------------------------------------------------------------------
## Wingtip vortices, the transonic vapour cone and low-level speed streaks.
func _build_aero_fx() -> void:
	for tip in _model.get("tips", []):
		var p := Effects.trail_particles(Color(1, 1, 1), 1.1, 40)
		p.lifetime = 1.1
		p.emitting = false
		p.local_coords = false
		var pm: ParticleProcessMaterial = p.process_material
		pm.gravity = Vector3.ZERO
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 1.2
		pm.spread = 25.0
		p.position = tip
		_model["root"].add_child(p)
		_vortex.append(p)

	# Prandtl-Glauert vapour: only the grazing silhouette should glow, so the
	# cone is shaded by a fresnel term instead of being additively flooded.
	var st := MeshKit.begin()
	MeshKit.cone(st, 0.35, 3.1, -2.6, 3.4, Vector3.ZERO, 18, false)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = vec3(0.82, 0.90, 1.0);
	ALPHA = pow(f, 3.0) * amount;
}
"""
	_shock_shader = ShaderMaterial.new()
	_shock_shader.shader = sh
	_shock_shader.set_shader_parameter("amount", 0.0)
	var sm_mesh: ArrayMesh = MeshKit.finish(st, _shock_shader)
	_shock = MeshKit.mi(sm_mesh, "ShockCone")
	_shock.position = Vector3(0, 0, 1.2)
	_shock.visible = false
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model["root"].add_child(_shock)

	_streaks = Effects.ember_particles(Color(0.92, 0.95, 1.0), 0.35, 90)
	_streaks.lifetime = 1.4
	_streaks.local_coords = false
	_streaks.emitting = false
	var sm: ParticleProcessMaterial = _streaks.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(34.0, 16.0, 34.0)
	sm.gravity = Vector3.ZERO
	sm.initial_velocity_min = 0.0
	sm.initial_velocity_max = 0.0
	sm.damping_min = 0.0
	sm.damping_max = 0.0
	_streaks.draw_pass_1.size = Vector2(0.25, 2.4)
	add_child(_streaks)

func _update_aero_fx() -> void:
	var q_norm: float = clampf(ias / 150.0, 0.0, 1.0)
	# vapour needs load and moist low air: strong pulls down low, little up high
	var moist: float = clampf(1.0 - global_position.y / 7000.0, 0.05, 1.0)
	var pull: float = clampf((absf(g_load) - 3.0) / 5.0, 0.0, 1.0)
	var alpha_v: float = clampf((rad_to_deg(absf(aoa)) - 9.0) / 14.0, 0.0, 1.0)
	var vortex: float = clampf(maxf(pull, alpha_v * 0.8) * moist * q_norm, 0.0, 1.0)
	for p in _vortex:
		var g: GPUParticles3D = p
		g.emitting = vortex > 0.05 and alive
		g.amount_ratio = clampf(vortex, 0.05, 1.0)

	if _shock:
		# a narrow window right around Mach 1, and only in damp low air
		var m := clampf(1.0 - absf(mach - 1.0) / 0.055, 0.0, 1.0)
		var a: float = m * 0.85 * moist
		_shock.visible = a > 0.02 and alive
		_shock_shader.set_shader_parameter("amount", a)
		_shock.scale = Vector3.ONE * lerpf(0.75, 1.1, m)

	if _streaks:
		var fast: float = clampf((linear_velocity.length() - 150.0) / 230.0, 0.0, 1.0)
		var low: float = clampf(1.0 - agl / 1200.0, 0.0, 1.0)
		var amt: float = fast * low
		_streaks.emitting = amt > 0.03 and alive
		_streaks.amount_ratio = clampf(amt, 0.03, 1.0)

## Rotate a control surface about its own hinge, preserving the rest frame.
func _deflect(node: Node3D, angle: float) -> void:
	if not is_instance_valid(node):
		return
	var rest: Basis = node.get_meta("rest", Basis())
	node.transform.basis = rest * Basis(Vector3(0, 1, 0), angle)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if ghost or not alive:
		return
	var xf := state.transform
	var b := xf.basis
	var pos := xf.origin
	var vel := state.linear_velocity
	var av := state.angular_velocity
	var speed := vel.length()
	var fwd := -b.z
	var up := b.y
	var right := b.x

	var ground := Sim.height_at(pos.x, pos.z)
	agl = pos.y - ground
	vspeed = vel.y
	var rho: float = RHO0 * exp(-maxf(pos.y, 0.0) / 8500.0)
	var q := 0.5 * rho * speed * speed
	ias = speed * sqrt(rho / RHO0)
	mach = speed / (340.3 - 0.0039 * clampf(pos.y, 0.0, 11000.0))

	var lv := b.inverse() * vel
	var vf := -lv.z
	if speed > 2.0:
		aoa = atan2(-lv.y, maxf(absf(vf), 1.0))
		beta = atan2(lv.x, maxf(absf(vf), 1.0))
	else:
		aoa = 0.0
		beta = 0.0

	# ---- engine ----------------------------------------------------------
	var spool: float = spec["spool"]
	# Overspeed protection: with the assist in, the engines are pulled back before
	# the airframe is over-stressed, the way a modern jet's limiter behaves. Fly
	# it with the assist off and you can tear the wings off.
	var demand := throttle
	if assist:
		var kias_now := ias * 1.94384
		var lim: float = float(spec["vne"])
		if kias_now > lim * 0.94:
			demand = minf(demand, clampf(1.0 - (kias_now - lim * 0.94) / (lim * 0.10),
				0.05, 1.0))
	power = move_toward(power, demand if fuel > 0.0 else 0.0, state.step / spool)
	var t_mil: float = spec["thrust_mil"]
	var t_ab: float = spec["thrust_ab"]
	var thrust := 0.0
	if power <= 0.78:
		thrust = t_mil * (power / 0.78)
	else:
		thrust = lerpf(t_mil, t_ab, (power - 0.78) / 0.22)
	thrust *= pow(clampf(rho / RHO0, 0.15, 1.0), 0.65)
	# Now that thrust is a real figure this is a real specific consumption:
	# thrust in newtons times sfc gives kilograms a second.
	const BURN_SCALE := 33800.0
	var burn: float = (t_mil * spec["sfc_mil"] if power <= 0.78 else t_ab * spec["sfc_ab"]) \
		* (power / BURN_SCALE) * state.step
	fuel = maxf(fuel - burn, 0.0)
	_burn += burn
	if _burn > 25.0:
		_burn = 0.0
		_refresh_mass()

	var force := fwd * thrust
	var torque := Vector3.ZERO

	# ---- aerodynamics ----------------------------------------------------
	var ge := 1.0 + 0.32 * clampf(1.0 - agl / maxf(spec["span"] * 0.85, 1.0), 0.0, 1.0)
	var stall_a: float = spec["cl_max_aoa"]
	var cl_lin: float = spec["cl_alpha"] * aoa
	var blend := clampf((absf(aoa) - stall_a) / deg_to_rad(12.0), 0.0, 1.0)
	var cl := lerpf(cl_lin, 1.5 * sin(2.0 * aoa), blend) * ge * _pen_lift
	# how much the high lift devices are worth. A fighter's plain flap is a
	# different thing from an airliner's slats and triple slotted flaps, and
	# giving the transports a fighter's increment is what made them need a
	# fighter's runway.
	cl += flap_anim * float(spec.get("flap_cl", 0.42))
	stalling = blend > 0.25 and speed > 20.0
	var cd: float = spec["cd0"]
	cd += cl * cl / (PI * spec["aspect"] * spec["oswald"])
	cd += 0.024 * gear_anim + 0.030 * flap_anim + (0.07 if airbrake else 0.0)
	cd += (1.0 - health / 100.0) * 0.02 + _pen_drag
	_rcs = spec["stealth"]
	for id in bays:
		var bb: Dictionary = bays[id]
		if bb["kind"] == "internal":
			cd += bb["drag"] * bb["anim"]
			_rcs += 1.4 * bb["anim"]
	# Wave drag: a hump centred just past Mach 1 that falls away again once the
	# shock system is established. Holding it on as a flat penalty pinned every
	# jet at about Mach 1.2 no matter how much thrust it had.
	if mach > 0.80:
		var m := (mach - 1.05) / 0.34
		cd += 0.022 * exp(-m * m)
	# skin friction and heating climb steeply once well supersonic, which is what
	# actually gives an airframe a top speed rather than a hard clamp
	if mach > 1.5:
		cd += 0.034 * pow(mach - 1.5, 2.0)

	# over the never-exceed speed the airframe starts coming apart
	var kias := ias * 1.94384
	if kias > spec["vne"]:
		var over: float = (kias - float(spec["vne"])) / 100.0
		cd += 0.012 * over
		_damage(over * over * 1.2 * state.step, "overspeed")
		_overspeed_warn -= state.step
		if is_in_group("player") and _overspeed_warn <= 0.0:
			_overspeed_warn = 3.0
			Sim.report("OVERSPEED — %d kt over the limit, the airframe is taking it"
				% int(kias - float(spec["vne"])), Sim.Ev.BAD)
	if speed > 1.0:
		var vdir := vel / speed
		var lift_dir := right.cross(vdir).normalized()
		var s_area: float = spec["wing_area"]
		var lift := lift_dir * q * s_area * cl
		var drag := -vdir * q * s_area * cd
		var side := -right * q * s_area * 1.35 * beta
		# a missing wing takes its lift with it, which is what rolls you over
		if absf(_pen_roll_bias) > 0.001:
			torque += fwd * _pen_roll_bias * q * spec["wing_area"] * 0.9
		force += lift + drag + side
		_dbg_lift = lift.length()
		_dbg_drag = drag.length()
	else:
		g_load = 0.0

	# ---- control power ---------------------------------------------------
	# Raw authority is deliberately large (a real stabilator makes megawatt-metres
	# of moment at speed). What keeps it flyable is the fly-by-wire law below,
	# which turns stick position into a *rate* command and closes the loop on
	# measured body rates, with AoA and G protection folded in. Switch the assist
	# off and you get the bare, relaxed-stability airframe.
	var qn := clampf(q / Q_REF, 0.0, 1.35)
	# What the aerodynamic surfaces can do. Vectoring aircraft keep a little of
	# this at low speed for the tails sitting in the jet wash, but most of their
	# low speed authority now comes from the nozzles themselves, below.
	var tvc: float = spec["tvc"] * clampf(power, 0.15, 1.0)
	var auth := maxf(qn, tvc * 0.35)
	var rr := av.dot(fwd)
	var pr := av.dot(right)
	var yr := av.dot(up)
	var p_cmd := in_pitch
	var r_cmd := in_roll
	var y_cmd := in_yaw
	if not assist:
		_pr_i = 0.0
		_rr_i = 0.0
	if assist:
		var v := maxf(speed, 55.0)
		var rate_cap: float = spec["max_pitch_rate"]
		# rate that corresponds to a true limit-g turn; the g feedback below
		# trims it if the airframe actually exceeds the limit, so this can be
		# generous instead of guessing low
		var g_cap: float = 9.81 * spec["g_limit"] / v
		var want_pr: float = in_pitch * (minf(rate_cap, g_cap) if in_pitch > 0.0 \
			else minf(rate_cap, 9.81 * 3.5 / v))
		var a_lim: float = spec["cl_max_aoa"]
		# Ride up to the limit rather than bouncing off it. A gain of 3 shoved
		# the nose back the instant the wing reached max lift, which is what
		# made the law feel like it was fighting the pilot instead of holding
		# the aeroplane at the edge of what the wing can do.
		if aoa > a_lim:
			want_pr = minf(want_pr, -(aoa - a_lim) * 1.7)
		elif aoa < -a_lim * 0.6:
			want_pr = maxf(want_pr, (-aoa - a_lim * 0.6) * 1.7)
		# below manoeuvre speed the law walls off the nose-high attitude that
		# would otherwise let you hang on the engines and mush
		var ias_kt := ias * 1.94384
		if ias_kt < 220.0:
			var att := asin(clampf(-b.z.y, -1.0, 1.0))
			var lim := deg_to_rad(lerpf(12.0, 55.0, clampf((ias_kt - 95.0) / 125.0, 0.0, 1.0)))
			if att > lim:
				want_pr = minf(want_pr, (lim - att) * 1.6)
		if on_ground and gear_anim > 0.9:
			want_pr = in_pitch * 0.35
		# A proportional-only rate loop settles with a standing error: at 250 m/s
		# it wanted 0.36 rad/s, held 0.28, and left the stabilator at a quarter
		# deflection while the pilot had the stick on the back stop. The integral
		# term is what actually closes the loop, so full aft stick delivers the
		# commanded rate instead of two thirds of it.
		var p_err := want_pr - pr
		var p_raw := p_err * 3.2 + _pr_i
		# Wind the integrator in at a rate the airframe can actually answer.
		# A gain tuned on a Raptor, which rolls at 4 rad/s, drives a Hercules at
		# 0.95 rad/s into a limit cycle: it demands authority faster than the
		# aeroplane can produce it, overshoots, and wallows.
		var i_auth: float = float(spec["max_pitch_rate"]) / 0.92
		if absf(p_raw) < 1.0 or signf(p_err) != signf(p_raw):
			_pr_i = clampf(_pr_i + p_err * state.step * 6.0 * i_auth, -1.0, 1.0)
		p_cmd = clampf(p_err * 3.2 + _pr_i, -1.0, 1.0)
		# hard g protection sits on top of the rate loop
		# A transient overshoot is allowed, as it is on a real jet: the limiter
		# holds the sustained case and does not clip every snatch of the stick.
		if g_load > spec["g_limit"] + 0.8 and p_cmd > 0.0:
			p_cmd *= clampf(1.0 - (g_load - spec["g_limit"] - 0.8) / 1.2, 0.0, 1.0)
		elif g_load < -3.2 and p_cmd < 0.0:
			p_cmd *= clampf(1.0 - (-g_load - 3.2) / 1.0, 0.0, 1.0)
		# roll is only trimmed close to the AoA limit, where it would depart
		var aoa_fade: float = clampf(1.0 - (absf(aoa) - a_lim * 0.78) / (a_lim * 0.5), 0.5, 1.0)
		var want_rr: float = in_roll * spec["max_roll_rate"] * aoa_fade
		var r_err := want_rr - rr
		var r_raw := r_err * 1.4 + _rr_i
		var r_auth: float = float(spec["max_roll_rate"]) / 4.1
		if absf(r_raw) < 1.0 or signf(r_err) != signf(r_raw):
			_rr_i = clampf(_rr_i + r_err * state.step * 2.5 * r_auth, -1.0, 1.0)
		r_cmd = clampf(r_err * 1.4 + _rr_i, -1.0, 1.0)
		# turn coordination: kill sideslip unless the pilot asks for it
		# beta > 0 means the nose sits left of the flight path, so the correcting
		# rudder command is *positive* (nose right). Getting this backwards makes
		# the damper drive the sideslip instead of killing it.
		y_cmd = clampf(in_yaw + beta * 4.0 + yr * 0.35, -1.0, 1.0)
	surf_pitch = p_cmd
	surf_roll = r_cmd
	surf_yaw = y_cmd

	# ---- thrust vectoring -------------------------------------------------
	# The nozzles take the same commands as the tails and swivel at a finite
	# rate. Deflecting the exhaust up pushes the tail down and the nose up, so
	# the force on the airframe tilts the other way from the jet; the moment
	# then falls out of where the nozzles are relative to the centre of mass,
	# rather than being a number invented for the purpose.
	# ---- STOVL ------------------------------------------------------------
	# The nozzle swivels down and the lift fan spins up. In the real aeroplane
	# the two are placed so their thrust is balanced about the centre of mass --
	# that is what the fan is for -- so the net effect is lift and attitude
	# control rather than an enormous pitching moment. Conversion is only
	# allowed slowly: at wingborne speed the doors would be torn off.
	if bool(spec.get("stovl", false)):
		var may_hover: bool = ias * 1.94384 < 260.0
		var want_h: float = 1.0 if (hover_cmd and may_hover) else 0.0
		jetborne = move_toward(jetborne, want_h, state.step / 3.5)
	else:
		jetborne = 0.0
	if jetborne > 0.001:
		# Against WEIGHT, not against the engine number. Sim thrust is about
		# fifteen times life so the jets feel right against the map, and hanging
		# the aeroplane off 92% of that gave twenty-seven g straight up. A STOVL
		# jet has a bit over one to one in the hover, and that is what this is.
		# The nozzle is pointing at the ground, so it is not pointing aft: take
		# the axial thrust away as the conversion proceeds, or the aeroplane
		# accelerates down the runway at full power while hovering.
		force -= fwd * thrust * jetborne
		force += up * (mass * 9.81 * 1.22) * clampf(power, 0.0, 1.0) * jetborne
		# reaction controls at the nose, tail and wingtips: attitude authority
		# that does not care what the airspeed is
		torque += right * p_cmd * spec["pitch_torque"] * 0.55 * jetborne
		torque += fwd * r_cmd * spec["roll_torque"] * 0.55 * jetborne
		torque += -up * y_cmd * spec["yaw_torque"] * 0.55 * jetborne
		# and a lot of damping, or it wallows around the hover like a pendulum
		torque -= av * mass * 2.2 * jetborne

	var tv_p: float = deg_to_rad(float(spec.get("tvc_pitch", 0.0)))
	var tv_y: float = deg_to_rad(float(spec.get("tvc_yaw", 0.0)))
	if (tv_p > 0.0 or tv_y > 0.0) and thrust > 0.0:
		var slew: float = deg_to_rad(80.0) * state.step
		nozzle_pitch = clampf(p_cmd * tv_p, nozzle_pitch - slew, nozzle_pitch + slew)
		nozzle_yaw = clampf(y_cmd * tv_y, nozzle_yaw - slew, nozzle_yaw + slew)
		var dir := (fwd * cos(nozzle_pitch) * cos(nozzle_yaw)
			- up * sin(nozzle_pitch) - right * sin(nozzle_yaw)).normalized()
		# swap the axial thrust already in the force sum for the vectored one
		force += (dir - fwd) * thrust
		torque += (b * (_nozzle_arm - center_of_mass)).cross(dir * thrust)
	else:
		nozzle_pitch = 0.0
		nozzle_yaw = 0.0
	torque += right * p_cmd * spec["pitch_torque"] * auth * _pen_pitch
	torque += fwd * r_cmd * spec["roll_torque"] * maxf(qn, tvc * 0.25) * _pen_roll_auth
	torque += -up * y_cmd * spec["yaw_torque"] * auth

	# aerodynamic damping and static stability (always present)
	torque -= fwd * rr * spec["roll_damp"] * (qn + 0.04)
	torque -= right * pr * spec["pitch_damp"] * (qn + 0.04)
	torque -= up * yr * spec["yaw_damp"] * (qn + 0.04)
	torque -= right * aoa * spec["pitch_stab"] * qn
	torque += -up * beta * spec["yaw_stab"] * qn * _pen_yaw
	# dihedral effect, but not while the undercarriage is holding the wings level
	torque -= fwd * beta * spec["roll_torque"] * (0.02 if on_ground else 0.10) * qn

	# ---- undercarriage ---------------------------------------------------
	var contacts := 0
	if gear_anim > 0.9:
		contacts = _gear_forces(state, force, torque, ground)
	on_ground = contacts > 0
	if on_ground:
		# An aircraft on its wheels is held straight by the tyres, not the fin,
		# and the damping has to rise with speed or a fast touchdown ground
		# loops: the F-35 lands at 170 kt and would swing 20 degrees off the
		# centreline and cartwheel. Roll is damped too, because once a main
		# wheel unloads the other one has the leverage to flip the aircraft.
		torque -= up * av.dot(up) * mass * (3.2 + 0.40 * speed)
		torque -= fwd * av.dot(fwd) * mass * (2.0 + 0.15 * speed)
	if on_ground and not _was_airborne:
		pass
	if _was_airborne and on_ground and _life_t > 1.2:
		_register_touchdown(vel, b)
	_was_airborne = not on_ground

	# ---- crash test ------------------------------------------------------
	var belly := 1.15 if gear_anim > 0.9 else 0.9
	if agl < belly and (gear_anim < 0.9 or absf(b.y.dot(Vector3.UP)) < 0.72):
		_impact(vel.length())
	if agl < -2.0:
		_impact(200.0)
	if pos.y < Sim.WATER_LEVEL and ground < Sim.WATER_LEVEL:
		Effects.dust(get_tree().current_scene, Vector3(pos.x, Sim.WATER_LEVEL, pos.z), 8.0)
		_impact(200.0)

	if debug_forces and Engine.get_physics_frames() % 120 == 0:
		print("  thrust=%9.0f  lift=%9.0f  drag=%9.0f  cl=%.3f cd=%.3f q=%.0f  gearN=%d  torque=%s" % [
			thrust, _dbg_lift, _dbg_drag, cl, cd, q, contacts, str(torque.round())])
		print("     mass=%.0f  vel=%.2f  step=%.5f" % [mass, state.linear_velocity.length(), state.step])
		print("     gear total=%s  fwd=%9.0f  av=%s" % [str(_dbg_gear.round()), _dbg_gear_fwd, str(state.angular_velocity)])
	# arrestor wire: a hook crossing a wire on the deck stops you in ~90 m
	if trapped:
		var spd := state.linear_velocity.length()
		_trap_t += state.step
		if spd > 1.2:
			force += -state.linear_velocity.normalized() * mass * 9.81 * 3.6
		if spd < 1.5 or _trap_t > 6.0:
			trapped = false
	elif hook_anim > 0.75 and on_ground and speed > 12.0 and not Sim.decks.is_empty():
		var tip := hook_tip()
		for d in Sim.decks:
			var l := Sim.deck_local(d, tip.x, tip.z)
			if absf(l.x) > 26.0:
				continue
			for wz in [-52.0, -38.0, -24.0, -10.0]:
				if (_prev_hook_z - wz) * (l.y - wz) < 0.0:
					trapped = true
					_trap_t = 0.0
					Effects.dust(get_tree().current_scene, tip, 2.0)
					Sfx.play_at(get_tree().current_scene, "thump", tip, -2.0, 0.8)
					if is_in_group("player"):
						Sim.report("TRAPPED — wire %d" % ([-52.0, -38.0, -24.0, -10.0].find(wz) + 1),
							Sim.Ev.GOOD)
					break
			_prev_hook_z = l.y
			break
	elif not Sim.decks.is_empty():
		var tip2 := hook_tip()
		for d in Sim.decks:
			_prev_hook_z = Sim.deck_local(d, tip2.x, tip2.z).y
			break

	# Load factor, worked out once everything is in the force sum. An
	# accelerometer strapped to the pilot reads the whole non-gravitational
	# specific force along his spine -- not just lift and thrust. Leaving drag
	# and side force out meant a hard turn with any sideslip or high alpha read
	# lower than it was, and the grey-out would let go part way through a
	# manoeuvre that was still pulling seven g.
	if not on_ground or contacts > 0:
		g_load = force.dot(up) / (mass * 9.81)
	_g_physiology(state.step)
	state.apply_central_force(force)
	state.apply_torque(torque)

func _gear_forces(state: PhysicsDirectBodyState3D, _force: Vector3, _torque: Vector3, _g: float) -> int:
	var xf := state.transform
	var com := xf.origin + xf.basis * center_of_mass
	var hits := 0
	_dbg_gear = Vector3.ZERO
	_dbg_gear_fwd = 0.0
	for g in spec["gear"]:
		var lp: Vector3 = g["pos"]
		var wp: Vector3 = xf * lp
		var gh := Sim.height_at(wp.x, wp.z)
		var comp: float = (gh + g["r"]) - wp.y
		if comp <= 0.0:
			continue
		comp = minf(comp, 0.55)
		hits += 1
		var n := Sim.normal_at(wp.x, wp.z)
		var arm := wp - com
		var pv := state.linear_velocity + state.angular_velocity.cross(arm)
		var vn := pv.dot(n)
		var k: float = mass * 9.81 * 3.4 / 0.20
		var c: float = 1.1 * sqrt(k * mass / 3.0)
		var fn: float = maxf(k * comp - c * vn, 0.0)
		fn = minf(fn, mass * 9.81 * 9.0)
		var f := n * fn
		# tyre friction in the ground plane
		var grip: float = Sim.surface_grip(wp.x, wp.z)
		var roll_dir := -xf.basis.z
		if g["steer"]:
			var steer := deg_to_rad(20.0) * -in_yaw * clampf(1.0 - pv.length() / 45.0, 0.06, 1.0)
			roll_dir = (-xf.basis.z).rotated(Vector3.UP, steer)
		roll_dir = (roll_dir - n * roll_dir.dot(n)).normalized()
		var lat_dir := n.cross(roll_dir).normalized()
		var v_lat := pv.dot(lat_dir)
		var v_roll := pv.dot(roll_dir)
		# tyres hold hard sideways; without this the jet skates down the runway
		var mu_lat: float = 1.7 * grip
		var f_lat: float = clampf(-v_lat * mass * 2.4, -mu_lat * fn, mu_lat * fn)
		var mu_roll: float = (0.62 if (wheel_brake and g["brake"]) else 0.022) * grip
		var f_roll: float = clampf(-v_roll * mass * 0.35, -mu_roll * fn, mu_roll * fn)
		f += lat_dir * f_lat + roll_dir * f_roll
		_dbg_gear += f
		_dbg_gear_fwd += f.dot(-xf.basis.z)
		state.apply_force(f, arm)
		if fn > mass * 9.81 * 6.0:
			_damage(6.0, "hard landing")
	return hits

func _register_touchdown(vel: Vector3, b: Basis) -> void:
	var pos := global_position
	var info := {
		"vs": vel.y,
		"gs": Vector2(vel.x, vel.z).length(),
		"offset": pos.x,
		"on_runway": Sim.on_runway(pos.x, pos.z),
		"remaining": (pos.z + Sim.RUNWAY_LEN * 0.5) if (-b.z).z < 0.0 else (Sim.RUNWAY_LEN * 0.5 - pos.z),
		"pitch": rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0))),
		"bank": rad_to_deg(atan2(b.x.y, b.y.y)),
	}
	last_touchdown = info
	touched_down.emit(info)
	if vel.y < -7.0:
		_damage(minf((-vel.y - 7.0) * 12.0, 100.0), "hard landing")

# --------------------------------------------------------------------------
func toggle_gear() -> void:
	if on_ground and gear_down:
		return
	gear_down = not gear_down

func toggle_bay(id := "") -> void:
	for k in bays:
		var b: Dictionary = bays[k]
		if b["kind"] != "internal":
			continue
		if id != "" and k != id:
			continue
		b["open"] = not b["open"]

func set_bays(open: bool) -> void:
	for k in bays:
		if bays[k]["kind"] == "internal":
			bays[k]["open"] = open

func any_bay_open() -> bool:
	for k in bays:
		var b: Dictionary = bays[k]
		if b["kind"] == "internal" and b["anim"] > 0.02:
			return true
	return false

## Display name and remaining count for any weapon id, gunship guns included.
func weapon_label(w: String) -> String:
	if w == "gun":
		return "GUN"
	for g in spec.get("guns", []):
		if String(g["id"]) == w:
			return String(g["name"])
	return String(WeaponSpec.get_spec(w)["name"])

func weapon_count(w: String) -> int:
	if w == "gun":
		return ammo
	for g in spec.get("guns", []):
		if String(g["id"]) == w:
			return -1                      # belt fed, no meaningful count
	return count_remaining(w)

func is_gunship_weapon(w: String) -> bool:
	for g in spec.get("guns", []):
		if String(g["id"]) == w:
			return true
	return false

func current_weapon() -> String:
	return weapon_types[selected] if selected < weapon_types.size() else "gun"

func cycle_weapon() -> void:
	for i in weapon_types.size():
		selected = (selected + 1) % weapon_types.size()
		if current_weapon() == "gun" or count_remaining(current_weapon()) > 0:
			return

func count_remaining(w: String) -> int:
	var n := 0
	for s in stores:
		if s["weapon"] == w and not s["gone"]:
			n += 1
	return n

func next_store(w: String) -> Dictionary:
	for s in stores:
		if s["weapon"] == w and not s["gone"]:
			return s
	return {}

## Returns "" if the shot went out, otherwise the reason it did not.
## Changing weapon abandons anything queued behind the bay doors. Without this
## a shot asked for with one store selected went off the moment the doors opened
## -- with whatever store you had switched to in the meantime.
func _note(t: String) -> void:
	if has_method("say"):
		call("say", t)

func set_weapon(idx: int) -> void:
	if idx == selected:
		return
	selected = idx
	if _pending_fire:
		_pending_fire = false
		_note("release cancelled")

func fire() -> String:
	if fire_cd > 0.0 or not alive:
		return "reloading"
	var w := current_weapon()
	if w == "gun":
		return "gun"
	var s := next_store(w)
	if s.is_empty():
		return "winchester"
	var bay: Dictionary = bays[s["bay"]]
	if bay["kind"] == "internal" and bay["anim"] < 0.96:
		# the jet has several bays; treat them as one switch so the pilot never
		# has to guess which door the selected round lives behind
		set_bays(true)
		_pending_fire = true
		return "bay opening — shot will go when the doors are clear"
	var ws := WeaponSpec.get_spec(w)
	# No lock is not a refusal. A radar round can be fired at any time; without
	# a lock it simply leaves with nothing to follow and flies where it was
	# pointed, which is the pilot's business rather than the rail's.
	var unguided: bool = ws["kind"] == "radar" and not locked
	var node: Node3D = s["node"]
	var xf := node.global_transform
	_pending_fire = false
	s["gone"] = true
	node.visible = false
	_refresh_mass()
	var m := Missile.new()
	# A guided bomb follows the designation if there is one: the pod's laser
	# spot beats whatever the radar happens to be holding, which is the whole
	# point of having a pod. Everything else keeps the radar target.
	var aim_node: Node3D = null if unguided else target
	# A point track is on a thing, and things move. Freezing the designation into
	# a spot at release meant a bomb aimed at a ship arrived where the ship had
	# been twenty seconds earlier, which is outside the lethal radius.
	if String(ws["kind"]) == "bomb" and is_instance_valid(designated_node):
		aim_node = designated_node
	elif String(ws["kind"]) == "bomb" and designated != Vector3.INF:
		var spot := DesignatedSpot.new()
		spot.global_position = designated
		get_tree().current_scene.add_child(spot)
		aim_node = spot
	m.launch(w, xf, linear_velocity, self, aim_node)
	get_tree().current_scene.add_child(m)
	store_released.emit(m)
	Sfx.play_at(get_tree().current_scene, "launch", xf.origin, -3.0, randf_range(0.92, 1.06))
	fire_cd = 0.55
	if unguided:
		_note("away — no lock, unguided")
	return ""

## AC-130 style battery: side firing shells lobbed at a designated point.
func gunship_gun() -> Dictionary:
	if not spec.get("gunship", false):
		return {}
	for g in spec["guns"]:
		if String(g["id"]) == current_weapon():
			return g
	return spec["guns"][0]

func fire_gunship(world: Node, aim: Vector3) -> bool:
	var g := gunship_gun()
	if g.is_empty() or gun_cd > 0.0 or not alive:
		return false
	gun_cd = 60.0 / float(g["rpm"])
	var ports: Array = spec["shape"].get("gun_ports", [Vector3(-2.4, -0.6, 0.0)])
	var muzzle: Vector3 = global_transform * (ports[randi() % ports.size()] as Vector3)
	var dir := (aim - muzzle)
	if dir.length() < 1.0:
		return false
	dir = dir.normalized()
	var sp: float = g["spread"]
	dir = (dir + Vector3(randf_range(-sp, sp), randf_range(-sp, sp), randf_range(-sp, sp))).normalized()
	var shell := Shell.new()
	shell.vel = dir * float(g["muzzle"]) + linear_velocity
	shell.damage = float(g["damage"])
	shell.blast = float(g["blast"])
	shell.shooter = self
	shell.team = team
	world.add_child(shell)
	shell.global_position = muzzle
	Effects.muzzle_flash(world, muzzle, dir, 2.6 if float(g["rpm"]) < 40.0 else 1.3)
	Effects.dust(world, muzzle, 1.6)
	Sfx.play_at(world, "boom" if float(g["rpm"]) < 40.0 else "rifle", muzzle,
		-2.0 if float(g["rpm"]) < 40.0 else -6.0, 0.55 if float(g["rpm"]) < 40.0 else 0.8, 3000.0)
	return true

func fire_gun(world: Node) -> bool:
	if ammo <= 0 or gun_cd > 0.0 or not alive:
		return false
	var g: Dictionary = spec["gun"]
	gun_cd = 60.0 / float(g["rpm"]) * 4.0     # tracer every 4th round
	ammo = maxi(ammo - 4, 0)
	var muzzle := global_transform * (g["pos"] as Vector3)
	var dir := -global_transform.basis.z
	var v: float = g["muzzle"]
	Effects.tracer(world, muzzle, dir * v + linear_velocity, self, g["damage"] * 4.0, team)
	Effects.muzzle_flash(world, muzzle, dir, 1.1)
	return true

# --------------------------------------------------------------------------
func _update_lock(delta: float) -> void:
	if target == null or not is_instance_valid(target) \
			or (target.has_method("is_alive") and not target.is_alive()):
		target = null
		locked = false
		lock_time = 0.0
		return
	var to: Vector3 = target.global_position - global_position
	var dist := to.length()
	var ang := rad_to_deg((-global_transform.basis.z).angle_to(to))
	var w := current_weapon()
	var ws := WeaponSpec.get_spec(w if w != "gun" else "aim9")
	var fov: float = 60.0 if w == "gun" else ws["seeker_fov"] * 0.6
	var rng: float = 20000.0 if w == "gun" else ws["range"] * 1.15
	if ang < fov and dist < rng:
		lock_time += delta
		locked = lock_time > (0.6 if w == "gun" else ws["lock_time"])
	else:
		lock_time = maxf(lock_time - delta * 2.0, 0.0)
		locked = false

func hit_radius() -> float:
	return 8.0

func flare_active() -> bool:
	return _flare_t > 0.0

## One press dispenses a salvo, not a single cartridge.
func drop_flare() -> void:
	if flares <= 0 or _flare_cd > 0.0:
		return
	_flare_cd = 0.45
	_flare_t = 3.4                      # window in which an IR seeker can be spoofed
	var n: int = mini(6, flares)
	flares -= n
	var b := global_transform.basis
	for i in n:
		var f := Flare.new()
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var spread := float(i) * 0.35
		f.vel = linear_velocity * 0.80 + b.x * side * randf_range(6.0, 16.0) \
			+ b.y * -randf_range(5.0, 13.0) + b.z * randf_range(3.0, 11.0)
		get_tree().current_scene.add_child(f)
		f.global_position = global_position + b.z * (2.2 + spread) \
			+ b.y * -0.6 + b.x * side * randf_range(0.5, 1.4)

func warn_missile() -> void:
	missile_warn = 2.0

func radar_cross_section() -> float:
	return _rcs

func _damage(amount: float, _cause := "") -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		explode()

func take_hit(amount: float, _from: Node = null) -> void:
	# A ghost is a picture of an aircraft somebody else is simulating; it has no
	# authority over its own state. Report the hit and let the owner apply it,
	# or the shooter watches a kill that never happened.
	if ghost and Sim.net != null and Sim.net.active:
		Sim.net.report_damage(self, amount)
		return
	# a solid hit is as likely to remove a control surface as it is to kill you
	var chance: float = clampf(amount / 90.0, 0.0, 0.85)
	if amount > 55.0 or randf() < chance:
		break_part(_pick_part())
	_damage(amount)

## A laser spot standing in for a target the seeker can hold. It is not a thing
## that can be shot, it is a place on the ground.
class DesignatedSpot extends Node3D:
	var team := -1
	func _ready() -> void:
		# in "hittable" so the fuse sweep finds it: a bomb that flies through
		# its own designation and carries on is no use to anybody
		add_to_group("hittable")
	var _life := 140.0
	func is_alive() -> bool:
		return true
	func hit_radius() -> float:
		return 2.0
	func take_hit(_a: float, _f: Node = null) -> void:
		pass
	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()

## Parts still attached, most fragile first.
func _pick_part() -> String:
	var order := ["canard_l", "canard_r", "stab_l", "stab_r", "fin_l", "fin_r",
		"canopy", "wing_l", "wing_r"]
	var avail: Array = []
	for id in order:
		if not lost.has(id) and _model.get("parts", {}).has(id):
			avail.append(id)
	if avail.is_empty():
		return ""
	# weight the tails and canopy well above the wings
	for i in avail.size():
		if randf() < 0.55:
			return avail[i]
	return avail[avail.size() - 1]

## Detach a part: it becomes tumbling debris and the airframe pays for it.
func break_part(id: String) -> void:
	if id == "" or lost.has(id):
		return
	var parts: Dictionary = _model.get("parts", {})
	if not parts.has(id):
		return
	var node: Node3D = parts[id]
	if not is_instance_valid(node):
		return
	lost[id] = true
	var xf := node.global_transform
	var arm := xf.origin - global_position
	node.get_parent().remove_child(node)
	var d := Debris.new()
	d.visual = node
	d.vel = linear_velocity + angular_velocity.cross(arm) \
		+ arm.normalized() * randf_range(3.0, 9.0) + Vector3(0, randf_range(0.0, 3.0), 0)
	d.spin = Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))
	d.smoking = id.begins_with("wing")
	get_tree().current_scene.add_child(d)
	d.global_transform = xf
	Effects.dust(get_tree().current_scene, xf.origin, 2.4)
	Sfx.play_at(get_tree().current_scene, "thump", xf.origin, -6.0, 1.5)
	# drop any control surface that lived on the part
	match id:
		"wing_l", "wing_r":
			var side := -1.0 if id == "wing_l" else 1.0
			_pen_lift = maxf(_pen_lift - 0.42, 0.16)
			_pen_roll_bias += -side * 0.42
			_pen_drag += 0.055
			_pen_roll_auth *= 0.45
			for a in _ailerons.duplicate():
				if signf(float(a["side"])) == signf(side):
					_shed(a["node"])
					_ailerons.erase(a)
			if _flaps.size() > 0:
				_shed(_flaps.pop_back())
		"canard_l", "canard_r":
			_pen_pitch *= 0.72
			_pen_drag += 0.008
		"stab_l", "stab_r":
			_pen_pitch *= 0.5
			_pen_drag += 0.012
			if id == "stab_l":
				_stab_l = null
			else:
				_stab_r = null
		"fin_l", "fin_r":
			_pen_yaw *= 0.5
			_pen_drag += 0.010
			if _rudders.size() > 0:
				_shed(_rudders.pop_back())
		"canopy":
			_pen_drag += 0.014
			canopy_open = false
			canopy_anim = 0.0
	if is_instance_valid(self):
		_report_part(id)

func _shed(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var xf := node.global_transform
	node.get_parent().remove_child(node)
	var d := Debris.new()
	d.visual = node
	d.vel = linear_velocity + Vector3(randf_range(-6, 6), randf_range(-2, 4), randf_range(-6, 6))
	d.spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	get_tree().current_scene.add_child(d)
	d.global_transform = xf

func _report_part(id: String) -> void:
	if not is_in_group("player"):
		return
	var pretty: String = {"canard_l": "left canard", "canard_r": "right canard",
		"wing_l": "left wing", "wing_r": "right wing", "stab_l": "left stabilator",
		"stab_r": "right stabilator", "fin_l": "left fin", "fin_r": "right fin",
		"canopy": "canopy"}.get(id, id)
	Sim.report("%s gone" % pretty, Sim.Ev.BAD)

func _impact(speed: float) -> void:
	if Sim.debug_weapons:
		print("[impact] %s at %.0f m/s, agl=%.0f alive=%s" % [name, speed, agl, str(alive)])
	if speed > 12.0:
		explode()
	else:
		_damage(35.0, "scrape")

## Grey-out and red-out. Tolerance is not a hard wall: vision goes at a rate
## set by how far over you are, and comes back slower than it went, which is
## why a series of hard pulls costs more than one long one.
const G_TOL := 5.5               # sustained +Gz a strained pilot in a suit holds
const G_TOL_NEG := -1.8
func _g_physiology(dt: float) -> void:
	# Square the overage rather than scaling it linearly. A pilot in a suit
	# holding a good strain sits at six g more or less indefinitely and loses
	# sight at nine in a few seconds, and only a quadratic gives you both: a
	# linear rate that greys you out at nine also greys you out at six.
	var over := g_load - G_TOL
	if over > 0.0:
		g_strain = clampf(g_strain + over * over * dt * 0.030, 0.0, 1.0)
	else:
		g_strain = clampf(g_strain - dt * 0.42, 0.0, 1.0)
	# negative g has far less headroom and arrives much faster
	var under := G_TOL_NEG - g_load
	if under > 0.0:
		g_red = clampf(g_red + under * under * dt * 0.35, 0.0, 1.0)
	else:
		g_red = clampf(g_red - dt * 0.60, 0.0, 1.0)
	g_peak = maxf(g_peak, g_load)
	g_min = minf(g_min, g_load)

func is_alive() -> bool:
	return alive

## What a shooter should lead. For a ghost the rigid body's own velocity is
## whatever the physics server derived from the last teleport, which is noise;
## the replicated value is the real one.
func get_velocity() -> Vector3:
	if ghost:
		return get_meta("net_vel", Vector3.ZERO)
	return linear_velocity

func explode() -> void:
	if not alive:
		return
	alive = false
	wrecked = true
	health = 0.0
	Effects.explosion(get_tree().current_scene, global_position, 14.0)
	for i in randi_range(2, 4):
		break_part(_pick_part())
	# the hulk keeps flying its ballistic arc, burning, until it hits something
	angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-2.0, 2.0), randf_range(-3.5, 3.5))
	var burn_trail := Effects.trail_particles(Color(0.35, 0.33, 0.32), 4.0, 40)
	burn_trail.lifetime = 3.2
	burn_trail.emitting = true
	add_child(burn_trail)
	var embers := Effects.ember_particles(Color(1.0, 0.55, 0.18), 2.2, 26)
	embers.emitting = true
	add_child(embers)
	var rd := Ragdoll.new()
	rd.spawn_from(Transform3D(global_transform.basis, global_transform * cockpit_offset()),
		linear_velocity * 0.35 + Vector3(0, 6.0, 0))
	get_tree().current_scene.add_child(rd)
	died.emit(self)


## Decoy flare: a hot billboard that flickers and tumbles away trailing embers
## and smoke, rather than the plain white ball it used to be.
class Flare extends Node3D:
	var vel := Vector3.ZERO
	var life := 5.0
	var _burn := 0.0
	var _core: MeshInstance3D
	var _mat: StandardMaterial3D
	var _spin := Vector3.ZERO

	func _ready() -> void:
		top_level = true
		_core = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.5, 1.5)
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_mat.albedo_texture = Effects.glow_texture()
		_mat.albedo_color = Color(1.0, 0.86, 0.55, 0.95)
		qm.material = _mat
		_core.mesh = qm
		_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_core)
		var embers := Effects.ember_particles(Color(1.0, 0.7, 0.25), 0.55, 20)
		embers.emitting = true
		add_child(embers)
		var smoke := Effects.trail_particles(Color(0.9, 0.9, 0.92), 1.1, 22)
		smoke.lifetime = 1.8
		smoke.emitting = true
		add_child(smoke)
		_spin = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		reset_physics_interpolation()

	func _physics_process(delta: float) -> void:
		life -= delta
		_burn += delta
		vel = vel.lerp(Vector3(0, -16.0, 0), delta * 0.55)
		global_position += vel * delta
		rotation += _spin * delta
		var fade: float = clampf(life / 2.2, 0.0, 1.0)
		var flick := 0.72 + 0.28 * sin(_burn * 47.0) * randf_range(0.6, 1.0)
		_core.scale = Vector3.ONE * (0.7 + 0.7 * fade) * flick
		_mat.albedo_color = Color(1.0, 0.86, 0.55, 0.95 * fade)
		if life <= 0.0:
			queue_free()


## A piece of airframe on its way to the ground.
class Debris extends Node3D:
	var visual: Node3D
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var smoking := false
	var life := 18.0

	func _ready() -> void:
		top_level = true
		if visual:
			add_child(visual)
			visual.transform = Transform3D.IDENTITY
		if smoking:
			var t := Effects.trail_particles(Color(0.32, 0.31, 0.30), 2.4, 24)
			t.lifetime = 2.4
			t.emitting = true
			add_child(t)
		reset_physics_interpolation()

	func _physics_process(delta: float) -> void:
		life -= delta
		vel += Vector3.DOWN * 9.81 * delta
		vel -= vel * vel.length() * 0.0016 * delta
		global_position += vel * delta
		rotation += spin * delta
		spin = spin.lerp(Vector3.ZERO, delta * 0.12)
		var g := Sim.height_at(global_position.x, global_position.z)
		if global_position.y <= g + 0.3:
			Effects.dust(get_tree().current_scene, Vector3(global_position.x, g, global_position.z), 2.6)
			queue_free()
		elif life <= 0.0:
			queue_free()


## Gunship shell: ballistic, explodes on impact.
class Shell extends Node3D:
	var vel := Vector3.ZERO
	var damage := 120.0
	var blast := 8.0
	var shooter: Node = null
	var team := 0
	var life := 140.0          # artillery arcs can be a minute in the air
	var arm_dist := 12.0       # fuse arming distance: see _physics_process
	var rocket := false        # launcher round: drawn as one, and pointed
	var _flown := 0.0

	func _ready() -> void:
		top_level = true
		add_to_group("shells")
		var mi := MeshInstance3D.new()
		if rocket:
			# a launcher round is a metre and a half of motor, and it is meant to
			# be watched off the rails: body, nose and a burning throat
			var body := CapsuleMesh.new()
			body.radius = 0.16
			body.height = 2.6
			body.radial_segments = 8
			body.rings = 2
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(0.30, 0.31, 0.33)
			bm.metallic = 0.5
			bm.roughness = 0.55
			body.material = bm
			mi.mesh = body
			mi.rotation.x = deg_to_rad(90.0)     # capsule is built along Y
			var flame := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.30
			fm.height = 1.5
			fm.radial_segments = 8
			fm.rings = 3
			var em := StandardMaterial3D.new()
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.albedo_color = Color(1.0, 0.72, 0.30)
			fm.material = em
			flame.mesh = fm
			flame.position = Vector3(0, 0, 1.5)
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(flame)
			var trail := Effects.trail_particles(Color(0.78, 0.78, 0.80), 1.6, 40)
			trail.lifetime = 2.6
			trail.emitting = true
			add_child(trail)
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.35
			sm.height = 0.7
			sm.radial_segments = 6
			sm.rings = 3
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.75, 0.35)
			sm.material = m
			mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		reset_physics_interpolation()

	func _physics_process(delta: float) -> void:
		life -= delta
		var from := global_position
		vel += Vector3.DOWN * 9.81 * delta
		var to := from + vel * delta
		global_position = to
		if rocket and vel.length_squared() > 4.0:
			# nose follows the trajectory, so it arcs over rather than sliding
			# sideways down the sky
			var up_ref := Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD
			look_at(to + vel, up_ref)
		_flown += from.distance_to(to)
		# A fuse does not arm at the muzzle. Without this a howitzer parked in a
		# line of vehicles detonated its own round nine metres out, on the tank
		# standing beside it, every single time it fired.
		if _flown < arm_dist:
			return
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == shooter:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			var np: Vector3 = n.global_position
			var r: float = n.hit_radius() if n.has_method("hit_radius") else 6.0
			if Geometry3D.get_closest_point_to_segment(np, from, to).distance_to(np) < r + blast * 0.4:
				_burst(to)
				return
		var bed := Sim.height_at(to.x, to.z)
		if to.y <= Sim.WATER_LEVEL and bed < Sim.WATER_LEVEL:
			# a shell striking the sea goes off at the surface
			Effects.splash(get_tree().current_scene,
				Vector3(to.x, Sim.WATER_LEVEL, to.z), maxf(blast * 0.8, 5.0))
			_burst(Vector3(to.x, Sim.WATER_LEVEL, to.z))
		elif to.y <= bed:
			_burst(Vector3(to.x, bed, to.z))
		elif life <= 0.0:
			queue_free()

	func _burst(at: Vector3) -> void:
		if Sim.debug_weapons and has_meta("aim"):
			var aim: Vector3 = get_meta("aim")
			var org: Vector3 = get_meta("origin", at)
			print("[shell] impact %.0f m from aim (range %.1f km); flew %.0f m, at=%s aim=%s life=%.1f" % [
				Vector2(at.x - aim.x, at.z - aim.z).length(),
				Vector2(aim.x - org.x, aim.z - org.z).length() * 0.001,
				Vector2(at.x - org.x, at.z - org.z).length(),
				str(at.round()), str(aim.round()), 140.0 - life])
		Effects.explosion(get_tree().current_scene, at, blast)
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == shooter:
				continue
			var d: float = n.global_position.distance_to(at)
			if d < blast * 2.2 and n.has_method("take_hit"):
				n.take_hit(damage * clampf(1.0 - d / (blast * 2.2), 0.15, 1.0),
					shooter if is_instance_valid(shooter) else null)
		queue_free()
