class_name NapalmStrike
extends Node3D
## The WHITE PHOSPHORUS / NAPALM streak: canisters along a line on the map,
## and then a strip of ground on fire for most of half a minute -- burning
## anyone in it, whichever side, and choking the street with smoke.

var from := Vector3.ZERO
var to := Vector3.ZERO
## Only the look of it: see `Killstreaks.call_picture`.
var picture := false
## Who called it, for the kill feed and the credit.
var owner_node: Node = null
## Seconds from the call to the canisters coming down.
var delay := 5.0

const BURN := 25.0
const FADE := 5.0
## How far apart the fires are along the line, how far either side of it the
## second row stands, and how big a fire is.
const STEP := 8.0
const SIDE := 6.0
const CELL_R := 6.5
## What a fire does to someone standing in it, a second.
const DPS := 18.0

var _t := 0.0
var _lit := false
var _cells: Array = []          # [centre, particles, light, phase]
## One fire's particle and draw materials, made once for every strike. Each
## cell built its own, and a run's worth of canisters landing together was
## fifty new materials -- and fifty pipelines to compile -- in the one frame.
static var _fire_pm: ParticleProcessMaterial = null
static var _fire_draw: Mesh = null
## How many strikes are lighting the ground. Each cell had its own light, and a
## run put fifty dynamic lights up at once; now a strike has one, and only so
## many strikes at a time do.
static var _lights_up := 0
const LIGHTS_MAX := 6
var _has_light := false

func _exit_tree() -> void:
	if _has_light:
		_has_light = false
		_lights_up -= 1

## A fire, sharing the one set of materials.
static func _fire() -> GPUParticles3D:
	if _fire_pm == null:
		var t: GPUParticles3D = Effects.ember_particles(Color(1.0, 0.55, 0.15), 2.6, 40)
		var pm: ParticleProcessMaterial = t.process_material
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 35.0
		pm.gravity = Vector3(0, 3.0, 0)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(CELL_R * 0.6, 0.3, CELL_R * 0.6)
		_fire_pm = pm
		_fire_draw = t.draw_pass_1
		t.free()
	var f := GPUParticles3D.new()
	f.process_material = _fire_pm
	f.draw_pass_1 = _fire_draw
	f.amount = 40
	f.lifetime = 1.6
	f.local_coords = false
	return f
var _tick := 0.0
var _smoke: SmokeScreen = null

func _ready() -> void:
	Sfx.play_at(get_tree().current_scene, "shot_far", from.lerp(to, 0.5), 6.0, 0.4, 6000.0)

func _process(delta: float) -> void:
	_t += delta
	if not _lit and _t >= delay:
		_lit = true
		_ignite()
	if not _lit:
		return
	var age: float = _t - delay
	var fade: float = clampf((age - BURN) / FADE, 0.0, 1.0)
	for c in _cells:
		var p: GPUParticles3D = c[1]
		if is_instance_valid(p):
			p.amount_ratio = 1.0 - fade
			if fade >= 1.0:
				p.emitting = false
		var l: Variant = c[2]
		if l != null and is_instance_valid(l):
			l.light_energy = (1.0 - fade) * (2.2 + sin(_t * 9.0 + float(c[3])) * 0.6)
	if age < BURN:
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.5
			_burn(0.5)
	if age > BURN + FADE + 1.0:
		queue_free()

func _ignite() -> void:
	var world := get_tree().current_scene
	var run: float = from.distance_to(to)
	var dir: Vector3 = (to - from).normalized() if run > 0.5 else Vector3.FORWARD
	var across: Vector3 = dir.cross(Vector3.UP).normalized()
	# One spot for a canister (`from` and `to` the same) -- it was the same
	# spot twice over, four fires where two were meant -- and a spot every
	# `STEP` along a line.
	var n: int = int(ceil(run / STEP)) if run > 0.5 else 0
	var k := 0
	var mid: Vector3 = from.lerp(to, 0.5)
	mid.y = Sim.height_at(mid.x, mid.z)
	# the burst as it catches: once for the strike, not once a fire
	var was_m: bool = Effects.mute_blast
	Effects.mute_blast = was_m or picture
	Effects.explosion(world, mid + Vector3(0, 0.5, 0), 3.0, false)
	Effects.mute_blast = was_m
	var light: OmniLight3D = null
	if _lights_up < LIGHTS_MAX:
		_lights_up += 1
		_has_light = true
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.omni_range = 18.0 + run * 0.5
		add_child(light)
		light.global_position = mid + Vector3(0, 2.0, 0)
	for i in n + 1:
		var on: Vector3 = from.lerp(to, float(i) / float(maxi(n, 1)))
		for s in [-1.0, 1.0]:
			var p: Vector3 = on + across * SIDE * s * 0.5
			p.y = Sim.height_at(p.x, p.z)
			var fire := _fire()
			fire.emitting = true
			add_child(fire)
			fire.global_position = p + Vector3(0, 0.4, 0)
			_cells.append([p, fire, light if k == 0 else null, float(k)])
			k += 1
	# and it smokes: a screen laid along the same line
	_smoke = SmokeScreen.new()
	_smoke.from = from
	_smoke.to = to
	_smoke.delay = 0.5
	world.add_child(_smoke)
	Sim.report("the strip is burning", Sim.Ev.GOOD)

## Everyone standing in a fire takes it, and can barely see for it.
func _burn(dt: float) -> void:
	if picture:
		return
	var by: Node = owner_node if is_instance_valid(owner_node) else null
	var hurt: Dictionary = {}
	for grp in ["infantry", "hittable"]:
		for n in get_tree().get_nodes_in_group(grp):
			if hurt.has(n) or not is_instance_valid(n) or not (n is Node3D):
				continue
			if not (n is Soldier or n is Walker):
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			var at: Vector3 = (n as Node3D).global_position
			for c in _cells:
				var cp: Vector3 = c[0]
				if Vector2(at.x - cp.x, at.z - cp.z).length() < CELL_R and absf(at.y - cp.y) < 3.0:
					hurt[n] = true
					n.take_hit(DPS * dt, by)
					if n.has_method("blind"):
						n.blind(0.6)
					break
