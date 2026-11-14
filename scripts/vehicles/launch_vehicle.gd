class_name LaunchVehicle
extends Node3D
## A crewed rocket: three stages and a capsule, flown by hand to orbit and back.
##
## Nothing about it is the aeroplane's flight model with the wings taken off.
## It is a mass, a thrust and a tank, under Newton's gravity:
##
## * each stage has its own dry mass, propellant, thrust and exhaust velocity,
##   and pushes harder as it empties -- the rocket equation is not written down
##   anywhere here, it is simply what burning mass off a thing does;
## * gravity is the planet's inverse square (and the moon's, for what that is
##   worth this close in), integrated in the planet's own frame in doubles, so
##   that going sideways at 7.8 km/s a couple of hundred kilometres up is an
##   orbit: it falls and keeps missing. Nothing holds it there but the sums;
## * the air is real on the way up and on the way down, and gone above it.
##
## The numbers are about a Saturn V's, because that is a rocket whose numbers
## are known to work: 1.2 g off the pad, two and a half minutes on the first
## stage, orbit about nine minutes later if it is flown properly, and plenty
## left in the third stage to change that orbit afterwards.
##
## It is flown as a rocket is: pitch, yaw and roll turn it, the throttle
## pushes it, and you stage when the tank is dry. There is no "go to orbit"
## key. Lift off straight up, tip over to the east a little at a time, hold
## the prograde marker once the air has thinned, and cut the engine when the
## low point of the orbit comes up out of the ground.

signal dismount_requested

## Two of them, and they are different machines.
##
## The orbital rocket is what puts a capsule round the planet and no more: two
## stages, a little over five hundred tonnes, and a capsule whose own engine is
## for coming home. The moon rocket is six times that -- a Saturn V's figures,
## near enough -- because going to the moon is not going a bit higher: it is
## another three kilometres a second on top of orbit to get there, most of
## another one to stop when it arrives, and a spacecraft with the tanks to do
## the stopping, all of which has to be lifted off the pad first.
##
## Each stage: dry mass and propellant (kg), thrust (N), specific impulse (s),
## length and radius (m), and how many engine bells it shows.
const KINDS := {
	"orbital": {"name": "ORBITAL ROCKET", "park": 200_000.0, "stages": [
		{"name": "FIRST STAGE", "dry": 22000.0, "prop": 400000.0,
			"thrust": 6800000.0, "isp": 300.0, "len": 30.0, "r": 1.9, "bells": 5},
		{"name": "SECOND STAGE", "dry": 5000.0, "prop": 90000.0,
			"thrust": 930000.0, "isp": 360.0, "len": 12.0, "r": 1.9, "bells": 1},
		{"name": "CAPSULE", "dry": 5000.0, "prop": 2000.0,
			"thrust": 40000.0, "isp": 310.0, "len": 6.0, "r": 1.9, "bells": 1},
	]},
	"lunar": {"name": "MOON ROCKET", "park": 185_000.0, "stages": [
		{"name": "FIRST STAGE", "dry": 135000.0, "prop": 2150000.0,
			"thrust": 34500000.0, "isp": 290.0, "len": 42.0, "r": 5.0, "bells": 5},
		{"name": "SECOND STAGE", "dry": 40000.0, "prop": 440000.0,
			"thrust": 5100000.0, "isp": 421.0, "len": 25.0, "r": 5.0, "bells": 5},
		{"name": "THIRD STAGE", "dry": 13500.0, "prop": 108000.0,
			"thrust": 1000000.0, "isp": 421.0, "len": 18.0, "r": 3.3, "bells": 1},
		# the capsule and the service module under it: its engine is the one
		# that stops it at the moon and brings it back
		{"name": "SPACECRAFT", "dry": 12000.0, "prop": 18000.0,
			"thrust": 91000.0, "isp": 314.0, "len": 8.0, "r": 2.0, "bells": 1},
	]},
}
var kind := "orbital"
var stages: Array = []
const G0 := 9.81
## How fast it can be turned, radians a second, and how quickly that comes on.
const TURN := 0.30
const ROLL := 0.55
const TURN_LAG := 2.5
## Anything slower than this onto the ground is a landing.
const SOFT := 12.0
const SAS_NAMES := ["FREE", "HOLD", "PROGRADE", "RETROGRADE"]

var occupied := false
var alive := true
var stage := 0
var throttle := 0.0
var landed := true
var chute := false
var sas := 1
var team := 0
## World-frame velocity, for cameras and anything else that asks.
var vel := Vector3.ZERO
var cam: Camera3D
var g_load := 1.0
var met := 0.0                    # mission elapsed time, seconds

var _s := PackedFloat64Array()
## Attitude in the planet's frame: -Z is the nose.
var _att := Basis()
var _prop: Array = []
var _rates := Vector3.ZERO
var _segs: Array = []
var _flame: MeshInstance3D
var _glow: OmniLight3D
var _smoke: GPUParticles3D
var _canopy: MeshInstance3D
var _chute_t := 0.0
var _snd: AudioStreamPlayer3D
var _cam_yaw := 0.6
var _cam_pitch := 0.25
var _cam_dist := 190.0
var _lifted := false
## The flying done for you: H. It does nothing a hand on the keys cannot -- it
## works the same throttle, the same attitude and the same staging -- and it
## lets go the moment the stick is touched. What it flies depends on where the
## vehicle is: off the pad, the ascent; in orbit in the moon rocket, the burn
## for the moon, the coast out to it, and the burn that stops it there.
var autopilot := false
## A harness is flying: the keyboard and the mouse are not.
var locked := false
## Which part of that it is on, and a line about it for the panel.
var program := ""
var auto_phase := ""
var _auto_aim := Vector3.ZERO
var _east0 := Vector3.RIGHT
## When the burn for the moon starts, on the space clock, and how long the
## flight out is reckoned to take.
var _tli_at := -1.0
var _trims := 0
## Standing on the moon, and where on it.
var on_moon := false
var _moon_off := Vector3.ZERO
## How much of the last tick was actually flown, in seconds: the warp, less
## whatever a burn or the air took back.
var flown := 0.0
## Close enough to the moon that it, not the planet, is what the figures on
## the panel are about: its sphere of influence, sixty-six thousand kilometres.
const MOON_SOI := 66_000_000.0
## The lowest the spacecraft is aimed to pass over the moon, and the orbit it
## is stopped into.
const PERILUNE := 160_000.0
## Above this the vehicle is drawn no higher, and the planet is drawn smaller
## instead: see `_place`.
const VIEW_CAP := 300_000.0
var _said: Dictionary = {}

func _init() -> void:
	top_level = true

## Stand it on the ground at a world point, nose up.
func setup(at: Vector3, which := "orbital") -> void:
	kind = which if KINDS.has(which) else "orbital"
	stages = KINDS[kind]["stages"]
	for st in stages:
		_prop.append(float(st["prop"]))
	var ground: float = maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z))
	var p: Vector3 = Sim.world_to_space(Vector3(at.x, ground + _below(), at.z))
	_s = Orbit.make(p, Vector3.ZERO)
	var up: Vector3 = p.normalized()
	# nose up, belly to the east: pitching "down" from here leans it eastward
	var east: Vector3 = Sim.chart_east
	_att = Basis.looking_at(up, -east)
	_east0 = east
	add_to_group("rockets")

func _ready() -> void:
	_build()
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 45000.0
	cam.top_level = true
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	_place()
	reset_physics_interpolation()

# ------------------------------------------------------------------ the model
## The node's origin is the foot of the capsule -- the top of the third stage
## -- and stays there however much of the stack has been dropped.
func _build() -> void:
	var white := MeshKit.mat(Color(0.90, 0.90, 0.88), 0.55, 0.15)
	var black := MeshKit.mat(Color(0.07, 0.07, 0.08), 0.6, 0.2)
	var z := 0.0
	var last: int = stages.size() - 1
	# from the top stage down to the first: each hangs below the last
	var built: Array = []
	built.resize(stages.size())
	for i in range(last - 1, -1, -1):
		var sd: Dictionary = stages[i]
		var L: float = sd["len"]
		var r: float = sd["r"]
		var seg := Node3D.new()
		seg.name = "Stage%d" % (i + 1)
		var st := MeshKit.begin()
		MeshKit.cone(st, r, r, z, z + L, Vector3.ZERO, 20)
		# engine bells at the bottom
		var bells: int = int(sd.get("bells", 1))
		for b in bells:
			var off := Vector3.ZERO
			if b > 0:
				var a: float = TAU * float(b) / 4.0 + PI * 0.25
				off = Vector3(cos(a), sin(a), 0.0) * r * 0.55
			MeshKit.cone(st, r * 0.16, r * (0.30 if bells > 1 else 0.42),
				z + L, z + L + r * 0.7, off, 10)
		seg.add_child(MeshKit.mi(MeshKit.finish(st, white), "Tank"))
		# the roll pattern: black bands and quarters, which is how you see it turn
		var bs := MeshKit.begin()
		MeshKit.cone(bs, r * 1.012, r * 1.012, z + L * 0.02, z + L * 0.10, Vector3.ZERO, 20)
		MeshKit.box(bs, Vector3(r * 0.9, r * 2.03, L * 0.22), Vector3(r * 0.5, 0.0, z + L * 0.72))
		seg.add_child(MeshKit.mi(MeshKit.finish(bs, black), "Bands"))
		if i == 0:
			var fs := MeshKit.begin()
			for f in 4:
				var fa: float = TAU * float(f) / 4.0
				var fo := Vector3(cos(fa), sin(fa), 0.0) * (r * 1.3)
				MeshKit.box(fs, Vector3(r * 0.64 if f % 2 == 0 else 0.25,
					0.25 if f % 2 == 0 else r * 0.64, r * 1.2),
					fo + Vector3(0.0, 0.0, z + L - r * 0.6))
			seg.add_child(MeshKit.mi(MeshKit.finish(fs, black), "Fins"))
		add_child(seg)
		built[i] = seg
		z += L
	# the capsule, on top: a cone, with whatever it carries its engine in
	var cap := Node3D.new()
	cap.name = "Capsule"
	var cr: float = float(stages[last]["r"])
	var cl: float = float(stages[last]["len"])
	var cs := MeshKit.begin()
	MeshKit.cone(cs, cr, cr, -cl + 2.6, 0.0, Vector3.ZERO, 16)
	MeshKit.cone(cs, 0.5, cr * 0.98, -cl, -cl + 2.6, Vector3.ZERO, 16)
	MeshKit.cone(cs, 0.45, cr * 0.55, 0.0, 1.2, Vector3.ZERO, 10)
	cap.add_child(MeshKit.mi(MeshKit.finish(cs, MeshKit.mat(Color(0.78, 0.79, 0.80), 0.35, 0.6)), "Hull"))
	add_child(cap)
	built[last] = cap
	_segs = built
	# the parachute, for the last five kilometres
	var ps := MeshKit.begin()
	MeshKit.cone(ps, 0.4, 9.0, -30.0, -22.0, Vector3.ZERO, 14, false)
	var pm := MeshKit.mat(Color(0.92, 0.42, 0.12), 0.9, 0.0)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_canopy = MeshKit.mi(MeshKit.finish(ps, pm), "Canopy")
	_canopy.visible = false
	cap.add_child(_canopy)
	var fst := MeshKit.begin()
	MeshKit.cone(fst, 1.0, 0.04, 0.0, 9.0, Vector3.ZERO, 12, false)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.albedo_color = Color(1.0, 0.84, 0.56, 0.8)
	fm.render_priority = 6
	_flame = MeshKit.mi(MeshKit.finish(fst, fm), "Flame")
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	add_child(_flame)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.74, 0.44)
	_glow.light_energy = 0.0
	_glow.omni_range = 900.0
	_glow.shadow_enabled = false
	add_child(_glow)
	_smoke = Effects.trail_particles(Color(0.93, 0.92, 0.90), 16.0, 150)
	_smoke.emitting = false
	add_child(_smoke)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = Sfx.get_clip("roar")
	_snd.unit_size = 420.0
	_snd.max_distance = 60000.0
	_snd.bus = &"Effects"
	add_child(_snd)

## How far the bottom of what is left hangs below the origin.
func _below() -> float:
	var d := 0.0
	for i in range(stage, stages.size() - 1):
		d += float(stages[i]["len"])
	return d + (float(stages[stage]["r"]) * 0.7 if stage < stages.size() - 1 else 1.3)

# -------------------------------------------------------------------- figures
func mass() -> float:
	var m := 0.0
	for i in range(stage, stages.size()):
		m += float(stages[i]["dry"]) + float(_prop[i])
	return m

func alt() -> float:
	return Orbit.radius(_s) - Sim.PLANET_R

func speed() -> float:
	return Orbit.speed(_s)

func fuel() -> float:
	return float(_prop[stage]) / float(stages[stage]["prop"])

## Speed this stage still has in it: exhaust velocity times the log of the
## mass ratio, which is all the rocket equation is.
func delta_v() -> float:
	var m0: float = mass()
	var m1: float = m0 - float(_prop[stage])
	return float(stages[stage]["isp"]) * G0 * log(m0 / maxf(m1, 1.0))

func display_name() -> String:
	return String(KINDS[kind]["name"]).capitalize()

func is_alive() -> bool:
	return alive

func get_velocity() -> Vector3:
	return vel

func mount(on: bool) -> void:
	occupied = on
	if on:
		cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Sim.space_rate = 1.0
		Sim.view_scale = 1.0
		Sim.view_moon = Vector3.INF

# --------------------------------------------------------------------- flying
func _unhandled_input(e: InputEvent) -> void:
	if not occupied:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := Sim.mouse_rel(e as InputEventMouseMotion)
		_cam_yaw -= mm.x * 0.0030
		_cam_pitch = clampf(_cam_pitch + mm.y * 0.0026, -1.45, 1.45)
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(_cam_dist * 0.88, 30.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(_cam_dist * 1.14, 4000.0)

func _controls(delta: float) -> Vector3:
	throttle = clampf(throttle + (Sim.strength(&"throttle_up")
		- Sim.strength(&"throttle_down")) * delta * 0.6, 0.0, 1.0)
	if Sim.tapped(&"brakes"):
		throttle = 0.0
	if Sim.tapped(&"cycle_target"):
		sas = (sas + 1) % SAS_NAMES.size()
		Sim.report("attitude: %s" % SAS_NAMES[sas], Sim.Ev.INFO)
	if Sim.tapped(&"fire"):
		next_stage()
	if Sim.tapped(&"interact"):
		dismount_requested.emit()
	if Sim.tapped(&"assist"):
		if autopilot:
			release("autopilot off — yours")
		else:
			engage()
	return Vector3(
		Sim.strength(&"pitch_up") - Sim.strength(&"pitch_down"),
		Sim.strength(&"roll_left") - Sim.strength(&"roll_right"),
		Sim.strength(&"yaw_left") - Sim.strength(&"yaw_right"))

## Drop what is spent and light what is next.
func next_stage() -> void:
	if stage >= stages.size() - 1:
		return
	if landed and not _lifted:
		Sim.report("still on the pad: SHIFT brings the throttle up", Sim.Ev.INFO)
		return
	# A stage comes off when it is empty, and not before. Dropped with its
	# tanks half full it took most of the vehicle's mass and all of that
	# stage's push with it in one frame: the stack leapt, the numbers on the
	# panel jumped to another rocket's, and a stage with hundreds of tonnes
	# still in it was left tumbling beside you. Burn it out, then let it go.
	if float(_prop[stage]) > 0.0:
		Sim.report("%s still has %d%% of its propellant: burn it out before it is dropped" % [
			String(stages[stage]["name"]).to_lower(), int(ceil(fuel() * 100.0))], Sim.Ev.BAD)
		return
	var seg: Node3D = _segs[stage]
	if is_instance_valid(seg):
		# It is not debris. It was going at whatever the vehicle was going at,
		# and it goes on doing so -- round the planet beside you, if that is
		# where it was let go, until the air or the ground has it.
		var d := SpentStage.new()
		d.host = self
		d.s = _s.duplicate()
		var back: Vector3 = _att.z
		for i in 3:
			d.s[3 + i] += back[i] * 2.5
		d.kd = 0.6 * PI * float(stages[stage]["r"]) * float(stages[stage]["r"]) \
			/ float(stages[stage]["dry"])
		d.basis0 = global_transform.basis
		var local: Transform3D = seg.transform
		remove_child(seg)
		d.add_child(seg)
		seg.transform = local
		get_tree().current_scene.add_child(d)
		d.global_transform = global_transform
	stage += 1
	Sim.report("staging — %s alight, %.0f m/s in it" % [
		String(stages[stage]["name"]).to_lower(), delta_v()], Sim.Ev.GOOD)
	if stage == stages.size() - 1:
		Sim.report("capsule only: its engine is for coming home. The parachute opens by itself low down.",
			Sim.Ev.INFO)

func _physics_process(delta: float) -> void:
	if not alive:
		if occupied and Sim.tapped(&"interact"):
			dismount_requested.emit()
		return
	var stick := Vector3.ZERO
	if occupied and not locked and not Sim.ui_modal and not Sim.typing:
		stick = _controls(delta)
	Orbit.sync()
	if autopilot:
		if stick.length() > 0.3:
			release("autopilot off — yours")
		else:
			_auto()
	var p: Vector3 = Orbit.pos_of(_s)
	var up: Vector3 = p.normalized()
	var h: float = p.length() - Sim.PLANET_R
	var sd: Dictionary = stages[stage]
	var m: float = mass()
	var burning: bool = throttle > 0.001 and float(_prop[stage]) > 0.0
	var thrust: float = float(sd["thrust"]) * throttle if burning else 0.0
	var nose: Vector3 = -_att.z
	var down_here: bool = landed or on_moon
	var warp: float = Sim.warp_at(h, burning) if not down_here else 1.0
	# an orbit that dips into the air is not one to be hurried round
	if warp > 100.0 and h < 2.0e6 and float(Orbit.apsides(_s)["pe"]) < 150000.0:
		warp = 100.0
	var span: float = delta * warp
	if burning:
		_prop[stage] = maxf(float(_prop[stage]) - thrust / (float(sd["isp"]) * G0) * span, 0.0)
		if float(_prop[stage]) <= 0.0 and not _said.has(stage):
			_said[stage] = true
			Sim.report("%s is dry — SPACE to stage" % String(sd["name"]).to_lower()
				if stage < stages.size() - 1 else "the last tank is dry", Sim.Ev.BAD)
	# ---- turning
	_turn(stick, delta)
	# ---- moving
	var acc_t: Vector3 = nose * (thrust / m)
	flown = delta
	if on_moon:
		_ride_moon(acc_t)
	elif landed:
		# It sits there until the engines are carrying more than its weight.
		if acc_t.dot(up) > Orbit.GM / p.length_squared() * 1.01:
			landed = false
			if not _lifted:
				_lifted = true
				Sim.report("lift-off", Sim.Ev.GOOD)
		g_load = 1.0
	if not landed and not on_moon:
		# drag area over mass: a long thin stack end on, a blunt capsule, or a
		# capsule under a canopy
		var area: float = 0.35 * PI * float(sd["r"]) * float(sd["r"])
		if stage == stages.size() - 1:
			area = 14.0
			var falling: bool = Orbit.vel_of(_s).dot(p) < 0.0
			if not chute and falling and h < 5200.0 and speed() < 260.0:
				chute = true
				_chute_t = 0.0
				_canopy.visible = true
				Sim.report("parachute", Sim.Ev.GOOD)
			if chute:
				# Reefed, and let out over six seconds. Thrown open all at
				# once it was fourteen hundred g: the canopy stopped the
				# capsule in its own length. Cut to the weight under it.
				_chute_t += span
				var open: float = smoothstep(0.0, 6.0, _chute_t)
				area = lerpf(14.0, 0.24 * m, open * open)
				_canopy.scale = Vector3.ONE * lerpf(0.25, 1.0, open)
		var kd: float = area / m
		var v0: Vector3 = Orbit.vel_of(_s)
		# In steps no longer than is honest where it is: a fiftieth of a second
		# under power or in the air, minutes at a time half way to the moon.
		var careful: bool = burning or h < 120000.0
		var left: float = span
		var done := 0.0
		var steps := 0
		while left > 1e-9 and steps < 600:
			var dt: float = minf(left, 0.02 if careful else Orbit.fair_step(_s))
			Orbit.step(_s, dt, acc_t, kd)
			left -= dt
			done += dt
			steps += 1
			if Orbit.moon_range(_s) < Orbit.MOON_R + _below():
				_meet_moon()
				break
			# down into the air on time warp: the rest of the tick is not flown
			if not careful and Orbit.radius(_s) - Sim.PLANET_R < 118000.0:
				break
		flown = done
		# what the crew feel: everything but gravity
		if done < 0.5:
			var felt: Vector3 = (Orbit.vel_of(_s) - v0) / maxf(done, 1e-6) \
				+ up * (Orbit.GM / p.length_squared())
			g_load = lerpf(g_load, felt.length() / G0, clampf(delta * 6.0, 0.0, 1.0))
		else:
			g_load = 0.0
		if not on_moon:
			_touch()
	met += flown if _lifted else 0.0
	# The space clock goes with the ship: the moon has to be where the flight
	# says it is, not where an hour of wall clock would have left it.
	if occupied:
		Sim.space_time += flown - delta
		Sim.space_rate = flown / maxf(delta, 1e-6)
	_place()
	_dress(burning, h)
	_heat(h)

## The heat of coming back. Whatever is left of the vehicle, going fast enough
## low enough, wears a sheath of plasma on whichever face is meeting the air
## -- the heat shield, flown blunt end first, the way it is meant to come in --
## and drags a trail of it behind; the crew feel it as a shudder.
var heat := 0.0
var _glow_p: Effects.Plasma = null

func _heat(h: float) -> void:
	if on_moon or landed:
		heat = 0.0
	else:
		heat = Effects.reentry_heat(h, Orbit.speed(_s))
	if _glow_p == null and heat > 0.01:
		_glow_p = Effects.plasma(self, float(stages[stage]["r"]) * 1.1)
	if _glow_p != null:
		_glow_p.size = float(stages[stage]["r"]) * 1.1
		# from the middle of what is left, out along the flight
		var mid: Vector3 = global_transform * Vector3(0.0, 0.0, _below() * 0.35)
		_glow_p.feed(mid + vel.normalized() * float(stages[stage]["r"]) * 0.6, vel, heat)
		if heat > 0.3 and not _said.has("heat"):
			_said["heat"] = true
			Sim.report("re-entry: %.1f km/s, the heat shield is taking it" % (speed() * 0.001),
				Sim.Ev.INFO)

## The moon, met: stood on if it was gentle, and the end of the flight if not.
func _meet_moon() -> void:
	var rel: PackedFloat64Array = Orbit.about_moon(_s, Orbit.now)
	var hit: float = Orbit.speed(rel)
	var out: Vector3 = Orbit.pos_of(rel).normalized()
	_moon_off = out * (Orbit.MOON_R + _below())
	on_moon = true
	throttle = 0.0
	if hit > SOFT or (-_att.z).dot(out) < 0.86:
		alive = false
		_ride_moon(Vector3.ZERO)
		_place()
		Sim.report("the vehicle is lost: it met the moon at %.0f m/s" % hit, Sim.Ev.BAD)
		for seg in _segs:
			if is_instance_valid(seg):
				(seg as Node3D).visible = false
		_flame.visible = false
		_glow.light_energy = 0.0
		return
	Sim.report("on the moon, at %.1f m/s. A sixth of the weight: SHIFT to leave." % hit,
		Sim.Ev.GOOD)

## Standing on the moon, it goes where the moon goes.
func _ride_moon(acc_t: Vector3) -> void:
	var m: PackedFloat64Array = Orbit.moon_state(Orbit.now)
	var out: Vector3 = _moon_off.normalized()
	for i in 3:
		_s[i] = m[i] + _moon_off[i]
		_s[3 + i] = m[3 + i]
	g_load = 0.165
	if acc_t.dot(out) > Orbit.MOON_GM / _moon_off.length_squared() * 1.02:
		on_moon = false
		for i in 3:
			_s[i] += out[i] * 2.0
		Sim.report("off the moon", Sim.Ev.GOOD)

## Near enough the moon that it is the thing being flown round.
func by_moon() -> bool:
	return Orbit.moon_range(_s) < MOON_SOI

## Attitude. The stick turns it at a rate; let go and it either holds where it
## is or swings onto the marker that has been asked for.
func _turn(stick: Vector3, delta: float) -> void:
	if (landed and not _lifted) or on_moon:
		return
	var want := Vector3(stick.x * TURN, stick.z * TURN, stick.y * ROLL)
	var hands_off: bool = stick.length() < 0.05
	var steered: bool = autopilot and _auto_aim != Vector3.ZERO
	if hands_off and (sas >= 2 or steered):
		# prograde is the way it is going round whatever it is going round
		var v: Vector3 = Orbit.vel_of(_s)
		if by_moon():
			v = Orbit.vel_of(Orbit.about_moon(_s, Orbit.now))
		if v.length() > 5.0 or steered:
			var aim: Vector3 = v.normalized() * (1.0 if sas == 2 else -1.0)
			if steered:
				aim = _auto_aim
			var nose: Vector3 = -_att.z
			var axis: Vector3 = nose.cross(aim)
			var off: float = nose.angle_to(aim)
			if axis.length() > 1e-5 and off > 0.002:
				# as body rates: about the body's own x and y
				var w: Vector3 = axis.normalized() * minf(off * 1.6, TURN)
				want = Vector3(w.dot(_att.x), w.dot(_att.y), 0.0)
	elif hands_off and sas == 0:
		# free: it keeps whatever turn it had, slowly dying away
		want = _rates * 0.995
	_rates = _rates.lerp(want, clampf(delta * TURN_LAG, 0.0, 1.0))
	_att = _att.rotated(_att.x, _rates.x * delta)
	_att = _att.rotated(_att.y, _rates.y * delta)
	_att = _att.rotated(_att.z, _rates.z * delta)
	_att = _att.orthonormalized()

## A stage that has been dropped. The same free fall as the vehicle it came
## off, in the same frame, and drawn by where it is *from that vehicle* -- the
## difference of two positions taken in doubles -- so that in orbit it hangs
## there and drifts slowly astern, instead of being a thing in the world's own
## coordinates falling straight down at ten metres a second squared.
class SpentStage extends Node3D:
	var host: LaunchVehicle = null
	var s := PackedFloat64Array()
	var kd := 0.0
	var basis0 := Basis()
	var _spin := Vector3(randf_range(-0.05, 0.05), randf_range(-0.03, 0.03),
		randf_range(-0.05, 0.05))
	var _turned := Vector3.ZERO

	func _init() -> void:
		top_level = true

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(host) or not host.alive:
			queue_free()
			return
		# as much time as the vehicle flew this tick, so warp keeps them together
		var span: float = maxf(host.flown, 0.0)
		Orbit.sync()
		var left: float = span
		var steps := 0
		while left > 1e-9 and steps < 300:
			var low: bool = Orbit.radius(s) - Sim.PLANET_R < 120000.0
			var dt: float = minf(left, 0.05 if low else Orbit.fair_step(s))
			Orbit.step(s, dt, Vector3.ZERO, kd)
			left -= dt
			steps += 1
		var rel := Vector3(s[0] - host._s[0], s[1] - host._s[1], s[2] - host._s[2])
		var h: float = Orbit.radius(s) - Sim.PLANET_R
		# gone: into the ground, or too far off to be anything but a dot
		if h < 0.0 or rel.length() > 120000.0:
			if h < 0.0 and rel.length() < 30000.0:
				Effects.explosion(get_tree().current_scene, global_position, 25.0)
			queue_free()
			return
		_turned += _spin * delta
		global_transform = Transform3D(
			Basis.from_euler(_turned) * basis0,
			host.global_position + Sim.planet_to_world_dir(rel))

## Where it is, in the planet's frame.
func space_pos() -> Vector3:
	return Orbit.pos_of(_s)

var _path := PackedVector3Array()
var _marks: Array = []
var _path_ms := -100000

## The flight from here if the engine is left alone, flown ahead: points in
## the planet's frame. Once round, if it is in orbit; down to the ground if it
## is not; out to the moon and round the back of it if that is where it is
## going. Round the moon, the lap is drawn where the moon is *now* -- as it is
## flown the moon carries it along, and drawn that way a circle round the
## moon comes out as a corkscrew a quarter of the way round the planet.
func path_ahead() -> PackedVector3Array:
	var ms: int = Time.get_ticks_msec()
	if ms - _path_ms < 1500 and not _path.is_empty():
		return _path
	_path_ms = ms
	_marks = []
	var out := PackedVector3Array()
	if landed or on_moon:
		_path = out
		return out
	var keep: float = Orbit.now
	var s: PackedFloat64Array = _s.duplicate()
	var near_moon: bool = by_moon()
	var moon0: Vector3 = Orbit.pos_of(Orbit.moon_state(keep))
	var orb: Dictionary = Orbit.apsides(_s)
	var span: float = 7.0 * 86400.0
	if near_moon:
		var mo: Dictionary = Orbit.apsides(Orbit.about_moon(_s, keep), Orbit.MOON_GM, Orbit.MOON_R)
		span = float(mo["period"]) if not is_inf(float(mo["period"])) else 2.0 * 86400.0
	elif not is_inf(float(orb["period"])):
		span = minf(float(orb["period"]), 12.0 * 86400.0)
	var t := 0.0
	var best_m := 1e30
	var best_m_at := Vector3.ZERO
	var hi := -1e30
	var hi_at := Vector3.ZERO
	var lo := 1e30
	var lo_at := Vector3.ZERO
	out.append(Orbit.pos_of(s))
	var steps := 0
	while t < span and steps < 2400:
		# no finer than a map needs
		var dt: float = minf(maxf(Orbit.fair_step(s) * 4.0, 4.0), span - t)
		Orbit.step(s, dt)
		t += dt
		steps += 1
		var at: Vector3 = Orbit.pos_of(s)
		var dm: float = Orbit.moon_range(s)
		if near_moon:
			at = moon0 + Vector3(s[0] - Orbit.mx, s[1] - Orbit.my, s[2] - Orbit.mz)
			if dm > hi:
				hi = dm
				hi_at = at
			if dm < lo:
				lo = dm
				lo_at = at
		else:
			var r: float = Orbit.radius(s)
			if r > hi:
				hi = r
				hi_at = at
			if r < lo:
				lo = r
				lo_at = at
			if dm < best_m:
				best_m = dm
				best_m_at = at
		out.append(at)
		if Orbit.radius(s) < Sim.PLANET_R or dm < Orbit.MOON_R:
			_marks.append(["IMPACT", at])
			break
	Orbit.now = keep
	Orbit._moon_at(keep)
	if near_moon:
		_marks.append(["HIGH %.0f km" % ((hi - Orbit.MOON_R) * 0.001), hi_at])
		_marks.append(["LOW %.0f km" % ((lo - Orbit.MOON_R) * 0.001), lo_at])
	else:
		if hi > Sim.PLANET_R + 1000.0:
			_marks.append(["HIGH %.0f km" % ((hi - Sim.PLANET_R) * 0.001), hi_at])
		if lo > Sim.PLANET_R:
			_marks.append(["LOW %.0f km" % ((lo - Sim.PLANET_R) * 0.001), lo_at])
		if best_m < 5.0e7:
			_marks.append(["PASSES THE MOON AT %.0f km" % ((best_m - Orbit.MOON_R) * 0.001),
				best_m_at])
	_path = out
	return out

## The points worth naming on that path: [what, where].
func path_marks() -> Array:
	return _marks

## Hand it to the autopilot: whichever program fits where the vehicle is.
func engage() -> void:
	var ap: Dictionary = Orbit.apsides(_s)
	_auto_aim = Vector3.ZERO
	if on_moon:
		Sim.report("nothing to fly from here: it is yours", Sim.Ev.INFO)
		return
	if by_moon():
		program = "capture"
	elif float(ap["pe"]) > 100000.0 and not is_inf(float(ap["ap"])):
		if kind != "lunar":
			Sim.report("in orbit already, and this rocket goes no further: it is yours",
				Sim.Ev.INFO)
			return
		if float(ap["ap"]) > 2.0e8:
			program = "coast"
		else:
			program = "moon burn"
			_tli_at = -1.0
	elif landed or alt() < 200000.0:
		program = "ascent"
		if kind == "lunar" and landed:
			_aim_plane()
	else:
		Sim.report("nothing to fly from here: it is yours", Sim.Ev.INFO)
		return
	autopilot = true
	Sim.report("autopilot has it: %s. Touch the stick to take it back." % program, Sim.Ev.INFO)

func release(why: String) -> void:
	autopilot = false
	program = ""
	auto_phase = ""
	_auto_aim = Vector3.ZERO
	if why != "":
		Sim.report(why, Sim.Ev.INFO)

func _auto() -> void:
	match program:
		"ascent":
			_auto_ascent()
		"moon burn":
			_auto_tli()
		"coast":
			_auto_coast()
		"capture":
			_auto_capture()
		_:
			release("")

## Never let the warp carry it past something it has to be awake for.
func _warp_for(seconds_to_go: float) -> void:
	while Sim.space_warp > 1.0 and Sim.space_warp / 60.0 > maxf(seconds_to_go, 0.0) / 12.0:
		Sim.warp_step(-1)

## Burn whatever stage is on the stack, dropping the dry ones as they go.
func _burn_on() -> void:
	if float(_prop[stage]) <= 0.0 and stage < stages.size() - 1:
		next_stage()
	throttle = 1.0

## How long the engine has to run to change the speed by `dv`.
func burn_time(dv: float) -> float:
	var ve: float = float(stages[stage]["isp"]) * G0
	var m0: float = mass()
	return m0 * (1.0 - exp(-absf(dv) / ve)) * ve / float(stages[stage]["thrust"])

## How long the fall from a low orbit out to the moon takes: half a lap of the
## long thin orbit that touches both.
func _transfer_time(r1: float) -> float:
	var a: float = (r1 + Orbit.MOON_DIST) * 0.5
	return PI * sqrt(a * a * a / Orbit.GM)

## Which way to lean off the pad so that the orbit it ends up in is one the
## moon will be in the plane of when the spacecraft gets there. The planet does
## not turn, so the pad stays in whatever plane it launches into: any plane
## through the pad and the place the moon will be is one that reaches it.
func _aim_plane() -> void:
	var here: Vector3 = Orbit.pos_of(_s).normalized()
	var r1: float = Sim.PLANET_R + float(KINDS[kind]["park"])
	var t_arr: float = Orbit.now + 600.0 + 2700.0 + _transfer_time(r1)
	var there: Vector3 = Orbit.pos_of(Orbit.moon_state(t_arr)).normalized()
	var toward: Vector3 = there - here * here.dot(there)
	if toward.length() > 0.05:
		_east0 = toward.normalized()

## The ascent, as a pilot would fly it: straight up to clear the pad, over a
## little at a time as the air thins, flat once it is out of it, and then
## holding that height while the speed across comes up to what an orbit there
## needs.
func _auto_ascent() -> void:
	var p: Vector3 = Orbit.pos_of(_s)
	var v: Vector3 = Orbit.vel_of(_s)
	var up: Vector3 = p.normalized()
	var h: float = p.length() - Sim.PLANET_R
	var climb: float = v.dot(up)
	var flat_v: Vector3 = v - up * climb
	var across: float = flat_v.length()
	var east: Vector3 = _east0 - up * _east0.dot(up)
	if across > 120.0:
		east = flat_v
	east = east.normalized()
	var ap: Dictionary = Orbit.apsides(_s)
	var park: float = float(KINDS[kind]["park"])
	# the last stage is the spacecraft: it is not spent getting to orbit
	if float(_prop[stage]) <= 0.0 and stage < stages.size() - 2:
		next_stage()
	# Round when it is going as fast across as an orbit at this height does.
	# Waiting for the low point to come up to some figure never ends if the
	# vehicle has levelled off below that figure: where it is *becomes* the low
	# point, and every second of burning after that only throws the far side
	# of the orbit further out -- to twenty-eight thousand kilometres, once.
	var v_round: float = sqrt(Orbit.GM / p.length())
	if h > 100000.0 and (across >= v_round * 1.003
			or (across >= v_round * 0.9995 and absf(climb) < 12.0)):
		throttle = 0.0
		sas = 2
		Sim.report("in orbit: %.0f by %.0f km, a lap every %s." % [
			float(ap["ap"]) * 0.001, float(ap["pe"]) * 0.001,
			_clock(float(ap["period"]))], Sim.Ev.GOOD)
		if kind == "lunar":
			release("The autopilot has let go. H again, when you are ready, flies it to the moon.")
		else:
			release("The autopilot has let go.")
		return
	# One rule the whole way up, not two taking turns.
	#
	# There were two: lean over by a schedule until the top of the arc reached
	# the height wanted, then hold that height. The second, switched to with
	# the vehicle still going up at over a kilometre a second, asked for the
	# nose thirty degrees *below* the horizon to stop the climb; that pulled
	# the top of the arc back under the figure, which handed it back to the
	# first, which pointed it up again -- and so on, every few seconds, the
	# whole stack nodding up and down through the end of the first stage.
	#
	# The schedule is what it flies low down, where the air decides. Above
	# that the nose goes wherever puts the climb to nothing exactly as the
	# height arrives: the vertical push that takes the climb off over the
	# height still to gain, plus the weight the speed is not yet carrying.
	# The two are blended by how near the top of the arc is to the height
	# wanted, so there is no moment at which one lets go and the other grabs.
	throttle = 1.0
	var sched: float = deg_to_rad(lerpf(90.0, 22.0,
		sqrt(clampf((h - 800.0) / 110000.0, 0.0, 1.0))))
	var g: float = Orbit.GM / p.length_squared()
	var a_t: float = float(stages[stage]["thrust"]) / mass()
	var carry: float = g - across * across / p.length()
	var room: float = park - h
	var a_v: float
	if room > 1500.0 and climb > 0.0:
		a_v = -climb * climb / (2.0 * room)
	else:
		a_v = -climb * 0.25 + room * 0.003
	# no climb or sink wanted at all once it is nearly round
	var hold: float = asin(clampf((carry + a_v) / maxf(a_t, 0.1), -0.25, 0.95))
	var top: float = float(ap["ap"]) if not is_inf(float(ap["ap"])) else park * 2.0
	var w: float = smoothstep(park * 0.55, park * 1.0, top) * smoothstep(45000.0, 70000.0, h)
	auto_phase = "climbing" if w < 0.5 else "levelling off"
	var el: float = lerpf(sched, hold, w)
	_auto_aim = (east * cos(el) + up * sin(el)).normalized()

## The burn for the moon.
##
## A spacecraft going to the moon does not point at it. It speeds up, at the
## right moment, by a little over three kilometres a second along the way it
## is already going, which stretches the far side of its orbit out to the
## moon's distance; half a lap later it is there. The right moment is when it
## is on the opposite side of the planet from where the moon *will be* when it
## arrives, five days on.
func _auto_tli() -> void:
	var p: Vector3 = Orbit.pos_of(_s)
	var v: Vector3 = Orbit.vel_of(_s)
	var r1: float = p.length()
	var ap: Dictionary = Orbit.apsides(_s)
	sas = 2
	if _tli_at < 0.0:
		# Find the pass: each guess at when it leaves says when it arrives,
		# which says where the moon will be, which says where it has to leave
		# from. A few rounds of that and it stops moving.
		var t_tr: float = _transfer_time(r1)
		var axis: Vector3 = p.cross(v).normalized()
		var rate: float = v.length() / r1
		var t_go: float = 0.0
		for i in 8:
			var there: Vector3 = Orbit.pos_of(Orbit.moon_state(Orbit.now + t_go + t_tr))
			var want: Vector3 = -(there - axis * axis.dot(there)).normalized()
			var ang: float = p.normalized().signed_angle_to(want, axis)
			if ang < 0.0:
				ang += TAU
			t_go = ang / rate
		var a_tr: float = (r1 + Orbit.MOON_DIST) * 0.5
		var dv: float = sqrt(Orbit.GM * (2.0 / r1 - 1.0 / a_tr)) - v.length()
		var lead: float = burn_time(dv) * 0.5
		if t_go < lead + 60.0:
			t_go += TAU / rate
		_tli_at = Orbit.now + t_go - lead
		_trims = 0
		Sim.report("the burn for the moon is in %s: %.0f m/s, %s of it. Time warp will bring it sooner." % [
			_clock(t_go - lead), dv, _clock(burn_time(dv))], Sim.Ev.INFO)
	var wait: float = _tli_at - Orbit.now
	if wait > 0.0:
		throttle = 0.0
		auto_phase = "burn for the moon in %s" % _clock(wait)
		_warp_for(wait)
		return
	# Burning. Until the far side of the orbit is out where the moon is.
	auto_phase = "burning for the moon"
	_burn_on()
	var far: float = float(ap["ap"]) + Sim.PLANET_R
	if is_inf(float(ap["ap"])) or far >= Orbit.MOON_DIST - 4.0e6:
		throttle = 0.0
		Sim.report("on the way: %.1f km/s, and it will be slowing all the way out" %
			(v.length() * 0.001), Sim.Ev.GOOD)
		program = "coast"

## The coast out, and the small corrections on the way.
##
## The burn is never exact, and the moon is a small thing to hit from four
## hundred thousand kilometres: a metre a second out at this end is a thousand
## kilometres at that one. So the path is flown ahead on paper, the miss is
## measured, and the speed is nudged by whatever takes the miss out.
func _auto_coast() -> void:
	throttle = 0.0
	sas = 1
	var dm: float = Orbit.moon_range(_s)
	auto_phase = "coasting to the moon, %.0f km to go" % (dm * 0.001)
	if _trims == 0 or (_trims == 1 and dm < 1.2e8):
		_trims += 1
		_trim()
	if dm < MOON_SOI:
		program = "capture"
		Sim.report("inside the moon's pull now: it is the moon it is falling round", Sim.Ev.GOOD)
		return
	# roughly how long until it is there, for the sake of the warp
	_warp_for(maxf((dm - MOON_SOI) / maxf(speed(), 200.0), 30.0))

## Fly a copy of the state ahead and say where it passes closest to the moon:
## [the vector from the moon's centre to that point, how many seconds off].
func _closest(s0: PackedFloat64Array) -> Array:
	var keep: float = Orbit.now
	var s: PackedFloat64Array = s0.duplicate()
	var best := 1e30
	var best_at := Vector3.ZERO
	var best_t := 0.0
	var t := 0.0
	var prev := 1e30
	while t < 9.0 * 86400.0:
		var dt: float = Orbit.fair_step(s)
		Orbit.step(s, dt)
		t += dt
		var d: float = Orbit.moon_range(s)
		if d < best:
			best = d
			best_t = t
			best_at = Vector3(s[0] - Orbit.mx, s[1] - Orbit.my, s[2] - Orbit.mz)
		# past it and going away again
		if d > prev and best < 1.0e8 and d > best * 1.5 + 2.0e6:
			break
		prev = d
	Orbit.now = keep
	Orbit._moon_at(keep)
	return [best_at, best_t]

## A midcourse correction: the change of speed that puts the closest pass at
## the height it is wanted, found by trying a metre a second each way and
## seeing what each does to the miss.
func _trim() -> void:
	var want_r: float = Orbit.MOON_R + PERILUNE
	var dv := Vector3.ZERO
	var miss := Vector3.ZERO
	for round_i in 6:
		var s0: PackedFloat64Array = _s.duplicate()
		for i in 3:
			s0[3 + i] += dv[i]
		miss = _closest(s0)[0]
		if absf(miss.length() - want_r) < 4000.0:
			break
		# the pass it should have made: the same side, the right distance
		var goal: Vector3 = miss.normalized() * want_r
		var cols: Array = []
		for k in 3:
			var s1: PackedFloat64Array = s0.duplicate()
			s1[3 + k] += 1.0
			cols.append((_closest(s1)[0] as Vector3) - miss)
		var jac := Basis(cols[0], cols[1], cols[2])
		if absf(jac.determinant()) < 1.0:
			break
		var step: Vector3 = jac.inverse() * (goal - miss)
		# not all of it at once: near the moon the path bends too sharply for
		# a straight-line guess to be trusted far
		if step.length() > 60.0:
			step = step.normalized() * 60.0
		dv += step
	if dv.length() < 0.01:
		return
	# paid for out of the tank, as any burn is
	var ve: float = float(stages[stage]["isp"]) * G0
	var used: float = mass() * (1.0 - exp(-dv.length() / ve))
	_prop[stage] = maxf(float(_prop[stage]) - used, 0.0)
	for i in 3:
		_s[3 + i] += dv[i]
	Sim.report("midcourse correction: %.1f m/s. Closest pass over the moon now %.0f km" % [
		dv.length(), (miss.length() - Orbit.MOON_R) * 0.001], Sim.Ev.INFO)

## Seconds until the lowest point of the path round the moon, from where the
## spacecraft is and how it is moving: negative once it is past.
func _to_perilune(rel: PackedFloat64Array) -> float:
	var gm: float = Orbit.MOON_GM
	var rv := Orbit.pos_of(rel)
	var vv := Orbit.vel_of(rel)
	var r: float = Orbit.radius(rel)
	var v2: float = Orbit.speed(rel) * Orbit.speed(rel)
	var vr: float = (rel[0] * rel[3] + rel[1] * rel[4] + rel[2] * rel[5]) / r
	var h2: float = rv.cross(vv).length_squared()
	var energy: float = v2 * 0.5 - gm / r
	var ecc: float = sqrt(maxf(1.0 + 2.0 * energy * h2 / (gm * gm), 0.0))
	if ecc < 1e-6:
		return 0.0
	var nu: float = acos(clampf((h2 / (gm * r) - 1.0) / ecc, -1.0, 1.0))
	if vr < 0.0:
		nu = -nu
	if energy >= 0.0:
		var a: float = gm / maxf(2.0 * energy, 1e-9)
		var f: float = 2.0 * atanh(clampf(sqrt((ecc - 1.0) / (ecc + 1.0)) * tan(nu * 0.5),
			-0.999999, 0.999999))
		return -(ecc * sinh(f) - f) * sqrt(a * a * a / gm)
	var a2: float = -gm / (2.0 * energy)
	var e_an: float = 2.0 * atan(sqrt((1.0 - ecc) / (1.0 + ecc)) * tan(nu * 0.5))
	return -(e_an - ecc * sin(e_an)) * sqrt(a2 * a2 * a2 / gm)

## Stopping at the moon.
##
## It arrives going faster than the moon can hold: left alone it swings round
## the back and is thrown out again. At the lowest point of the pass the engine
## is run against the way it is going until it is slow enough to stay.
func _auto_capture() -> void:
	var rel: PackedFloat64Array = Orbit.about_moon(_s, Orbit.now)
	var orb: Dictionary = Orbit.apsides(rel, Orbit.MOON_GM, Orbit.MOON_R)
	var r: float = Orbit.radius(rel)
	var sp: float = Orbit.speed(rel)
	var round_v: float = sqrt(Orbit.MOON_GM / r)
	var bound: bool = not is_inf(float(orb["ap"]))
	sas = 3
	# round enough, and it is done
	if bound and (float(orb["ap"]) < float(orb["pe"]) + 250000.0 or sp <= round_v * 1.002):
		throttle = 0.0
		sas = 1
		Sim.report("in orbit round the moon: %.0f by %.0f km, a lap every %s" % [
			float(orb["ap"]) * 0.001, float(orb["pe"]) * 0.001,
			_clock(float(orb["period"]))], Sim.Ev.GOOD)
		release("The autopilot has let go.")
		return
	if throttle > 0.0:
		auto_phase = "braking into orbit round the moon"
		_burn_on()
		return
	# Coming in. Start the burn half its own length before the low point, so
	# the middle of it is at the bottom where it does the most good.
	var rp: float = float(orb["pe"]) + Orbit.MOON_R
	var vp: float = sqrt(maxf(sp * sp + 2.0 * Orbit.MOON_GM * (1.0 / rp - 1.0 / r), 0.0))
	var need: float = vp - sqrt(Orbit.MOON_GM / rp)
	var lead: float = burn_time(need) * 0.5
	var t_low: float = _to_perilune(rel)
	auto_phase = "lowest point over the moon in %s, at %.0f km" % [_clock(t_low),
		float(orb["pe"]) * 0.001]
	if t_low < -20.0 and not bound:
		release("past the moon without stopping: it is yours")
		return
	if t_low <= lead:
		_burn_on()
		return
	_warp_for(t_low - lead)

## The ground: stood on, landed on, or flown into.
func _touch() -> void:
	var at: Vector3 = Sim.space_to_world(Orbit.pos_of(_s))
	if alt() > 9000.0:
		return
	var ground: float = maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z))
	var clear: float = at.y - ground - _below()
	if clear > 0.0:
		return
	var p: Vector3 = Orbit.pos_of(_s)
	var v: Vector3 = Orbit.vel_of(_s)
	if v.dot(p) > 0.0 and clear > -0.5:
		return                          # going up off it
	var hit: float = v.length()
	# set it back on the surface
	var up: Vector3 = p.normalized()
	var fixed: Vector3 = up * (p.length() - clear)
	for i in 3:
		_s[i] = fixed[i]
		_s[3 + i] = 0.0
	landed = true
	throttle = 0.0
	var upright: bool = (-_att.z).dot(up) > 0.86 or stage == stages.size() - 1
	if hit > SOFT or not upright:
		_wreck(hit)
		return
	var wet: bool = Sim.height_at(at.x, at.z) < Sim.sea_at(at.x, at.z)
	Sim.report("%s at %.1f m/s — U to climb out" % [
		"splashdown" if wet else "touchdown", hit], Sim.Ev.GOOD)
	_canopy.visible = false
	chute = false

func _wreck(hit: float) -> void:
	alive = false
	_place()
	Effects.explosion(get_tree().current_scene, global_position,
		40.0 if stage < stages.size() - 1 else 10.0)
	Sim.report("the vehicle is lost: it met the ground at %.0f m/s" % hit, Sim.Ev.BAD)
	for seg in _segs:
		if is_instance_valid(seg):
			(seg as Node3D).visible = false
	_flame.visible = false
	_glow.light_energy = 0.0
	_smoke.emitting = false
	throttle = 0.0

## Where the node is. The state is the planet's; the world is wherever the
## chart happens to be, so this is worked out afresh every tick and a chart
## move costs it nothing.
##
## Only so high, though. The world's coordinates are single precision: three
## hundred kilometres up they are good to three centimetres, and at the moon's
## distance to thirty metres -- a spacecraft drawn there would be a smear, and
## its camera another one. So above the cap it is drawn AT the cap, and the
## planet is drawn smaller by exactly as much as would make it look as it does
## from where the spacecraft really is: the same disc, the same horizon, the
## same place in the sky. `Sim.view_scale` is that shrink, which the planet,
## its air and its cloud all read; `Sim.view_moon` is where the moon is from
## here, worked out in doubles before anything is rounded.
func _place() -> void:
	var r: float = Orbit.radius(_s)
	var shown: float = minf(r, Sim.PLANET_R + VIEW_CAP)
	var at: Vector3 = Sim.space_to_world(Orbit.pos_of(_s) * (shown / r))
	vel = Sim.planet_to_world_dir(Orbit.vel_of(_s))
	var b := Basis(Sim.planet_to_world_dir(_att.x), Sim.planet_to_world_dir(_att.y),
		Sim.planet_to_world_dir(_att.z))
	global_transform = Transform3D(b.orthonormalized(), at)
	if occupied:
		Sim.view_scale = shown / r
		Sim.view_moon = Vector3(Orbit.mx - _s[0], Orbit.my - _s[1], Orbit.mz - _s[2])

## Flame, light and smoke.
func _dress(burning: bool, h: float) -> void:
	# Sized by the engines, not by the tank above them. It went by the stage's
	# radius, so the second stage -- the same ten metres across as the first,
	# on a seventh of the thrust -- trailed the same fire, and the capsule's
	# little engine burned like a booster. A plume's width goes as the square
	# root of the thrust making it: 4.4 m of flame under the first stage, 1.7
	# under the second, three quarters of a metre under the third, and a
	# blowlamp under the capsule.
	var sd: Dictionary = stages[stage]
	var core: float = 0.75 * sqrt(float(sd["thrust"]) * 1.0e-6)
	var tail := Vector3(0.0, 0.0, _below())
	_flame.visible = burning
	_flame.position = tail
	if burning:
		# ...and it spreads as the air thins, the way a real one does: a
		# pencil at the pad, a wide pale fan by the time it is in vacuum
		var wide: float = core * (1.0 + clampf(h / 45000.0, 0.0, 2.6))
		var long: float = core * (9.0 + throttle * 13.0) * (0.94 + 0.12 * sin(met * 53.0))
		_flame.scale = Vector3(wide, wide, long / 9.0)
	_glow.position = tail + Vector3(0, 0, core * 2.0)
	_glow.light_energy = (3.0 + core * 3.0) * throttle if burning else 0.0
	_glow.omni_range = 120.0 + core * 200.0
	_smoke.position = tail
	_smoke.emitting = burning and h < 45000.0
	_smoke.scale = Vector3.ONE * clampf(core / 4.4, 0.08, 1.0)
	# Heard through the air and, above it, only through the structure.
	if burning:
		_snd.position = tail
		_snd.volume_db = lerpf(-6.0, 14.0, throttle) - clampf(h / 9000.0, 0.0, 22.0)
		_snd.pitch_scale = 0.55 if stage == 0 else 0.8
		if not _snd.playing:
			_snd.play()
	elif _snd.playing:
		_snd.stop()

# --------------------------------------------------------------------- camera
func _process(_delta: float) -> void:
	if cam == null or not cam.current:
		return
	var xf: Transform3D = get_global_transform_interpolated()
	# Level with the horizon wherever it is, looking at the middle of the stack.
	var up: Vector3 = Sim.up_at(xf.origin)
	if Sim.view_moon != Vector3.INF and Sim.view_moon.length() < 2.0e7:
		up = -Sim.planet_to_world_dir(Sim.view_moon).normalized()
	var mid: Vector3 = xf.origin + xf.basis.z * (_below() * 0.45)
	var ref: Vector3 = up.cross(Vector3.RIGHT)
	if ref.length() < 0.1:
		ref = up.cross(Vector3.BACK)
	ref = ref.normalized()
	var side: Vector3 = up.cross(ref).normalized()
	var flat: Vector3 = ref * cos(_cam_yaw) + side * sin(_cam_yaw)
	var off: Vector3 = (flat * cos(_cam_pitch) + up * sin(_cam_pitch)) * _cam_dist
	var eye: Vector3 = mid + off
	# not under the ground while it is on the pad
	if xf.origin.y < 30000.0 and Sim.view_scale > 0.999:
		eye.y = maxf(eye.y, maxf(Sim.height_at(eye.x, eye.z), Sim.sea_at(eye.x, eye.z)) + 2.0)
	# the shudder of coming in, a few centimetres of it at the worst
	if heat > 0.05:
		eye += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * heat * 0.5
	cam.global_position = eye
	cam.look_at(mid, up)

# -------------------------------------------------------------------- readout
## What the page shows, top to bottom.
func readout() -> PackedStringArray:
	var out := PackedStringArray()
	var p: Vector3 = Orbit.pos_of(_s)
	var body := "the moon" if by_moon() else ""
	var st: PackedFloat64Array = _s
	var gm: float = Orbit.GM
	var br: float = Sim.PLANET_R
	if body != "":
		st = Orbit.about_moon(_s, Sim.space_time)
		gm = Orbit.MOON_GM
		br = Orbit.MOON_R
	var rp: Vector3 = Orbit.pos_of(st)
	var v: Vector3 = Orbit.vel_of(st)
	var up: Vector3 = rp.normalized()
	var sp: float = v.length()
	var climb: float = v.dot(up)
	var across: float = sqrt(maxf(sp * sp - climb * climb, 0.0))
	var h: float = Orbit.radius(st) - br
	out.append("%s — %s   T+%s" % [String(KINDS[kind]["name"]),
		String(stages[stage]["name"]), _clock(met)])
	out.append("ALTITUDE  %s%s" % [_dist(h), (" over " + body) if body != "" else ""])
	out.append("SPEED  %.0f m/s   ( %.0f up, %.0f across )" % [sp, climb, across])
	var ap: Dictionary = Orbit.apsides(st, gm, br)
	if is_inf(float(ap["ap"])):
		out.append("%s — lowest point %s" % ["passing the moon, not held by it" if body != ""
			else "leaving the planet", _dist(float(ap["pe"]))])
	else:
		out.append("HIGH POINT  %s   LOW POINT  %s" % [_dist(float(ap["ap"])),
			_dist(float(ap["pe"]))])
		if float(ap["pe"]) > (15000.0 if body != "" else 100000.0):
			out.append("IN ORBIT%s — one lap takes %s" % [(" ROUND THE MOON" if body != "" else ""),
				_clock(float(ap["period"]))])
		elif float(ap["ap"]) > 100000.0 and body == "":
			out.append("not an orbit yet: it needs %.0f m/s across at this height" %
				Sim.orbit_speed(h))
	var pitch: float = rad_to_deg(asin(clampf((-_att.z).dot(up), -1.0, 1.0)))
	out.append("NOSE  %+.0f deg above the horizon   ATTITUDE %s" % [pitch,
		("AUTOPILOT: " + auto_phase) if autopilot else SAS_NAMES[sas]])
	out.append("THROTTLE %d%%   PROPELLANT %d%%   %.0f m/s left in this stage" % [
		int(throttle * 100.0), int(fuel() * 100.0), delta_v()])
	out.append("%.1f g   GRAVITY HERE %.2f m/s2   TIME WARP x%d%s" % [g_load,
		gm / maxf(rp.length_squared(), 1.0), int(Sim.space_warp),
		"" if Sim.space_rate > 1.0 or Sim.space_warp <= 1.0 else " (held: under power or in the air)"])
	if body == "":
		var md: float = (Sim.moon_dir() * Sim.MOON_DIST - p).length()
		out.append("MOON  %.0f km" % (md * 0.001))
	else:
		out.append("PLANET  %.0f km" % (p.length() * 0.001))
	return out

static func _dist(m: float) -> String:
	if absf(m) < 10000.0:
		return "%.0f m" % m
	return "%.1f km" % (m * 0.001)

static func _clock(s: float) -> String:
	var t: float = floor(maxf(s, 0.0))
	var hrs: int = int(t / 3600.0)
	var mins: int = int(fmod(t, 3600.0) / 60.0)
	var secs: int = int(fmod(t, 60.0))
	if hrs > 0:
		return "%d:%02d:%02d" % [hrs, mins, secs]
	return "%02d:%02d" % [mins, secs]
