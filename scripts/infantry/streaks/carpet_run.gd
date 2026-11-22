class_name CarpetRun
extends Node3D
## A B-2 down a line the player drew on the map, laying a carpet of bombs
## along it. It comes in from well short of the line at height, lets each bomb
## go early enough that it falls onto its own stretch of the line -- worked out
## by dropping one in the same flight model the bombs fly -- and goes on out the
## far side. The bombs are real: they fall, and where they land they go off as
## the match's own bombs do, credited to the man who called it.

## A picture of a strike called on another machine: flies and goes off
## here, and hurts nobody. See `Killstreaks.call_picture`.
var picture := false
## What flies it and how. As set out here it is the B-2's carpet; the
## airstrike sets it up as a pair of strike jets low and fast with a stick
## of bombs (see `_call("strike_at")`). One run, so the release is worked
## out the same way for both and the bombs land on the line either way.
var spec_id := "b2"
## What each canister is: "" a bomb, "smoke" a smoke bank where it lands,
## "wp" white phosphorus burning where it lands, "drones" a switchblade
## off the ramp -- which circles over `drone_centre` looking.
var payload := ""
var drone_centre := Vector3.ZERO
var speed := 230.0
var height := 1100.0
## Between canisters. Each one opens over the line and covers sixty metres
## of it with bomblets, so the footprints overlap at this.
var spacing := 40.0
var longest := 600.0
var run_in := 7000.0
var cluster := true
var load_weapon := "cbu97"
var label := "B-2"
var min_bombs := 6
var max_bombs := 16
## A second aircraft on the leader's wing, in the run's own frame (x out to
## the right, z back), dropping every other bomb from its own track.
var wing := Vector3.ZERO
var arena: CqbMatch = null
var from := Vector3.ZERO
var to := Vector3.ZERO
var bombs := 0
var eta := 0.0
var _dir := Vector3.FORWARD
var _start := Vector3.ZERO
var _along := 0.0
var _drops: Array = []            # along-track distances to let go at
var _dropped := 0
var _end := 0.0

func _init() -> void:
	top_level = true

func _enter_tree() -> void:
	if not _drops.is_empty():
		return
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length: float = minf(flat.length(), longest)
	_dir = flat.normalized() if flat.length() > 1.0 else Vector3.FORWARD
	bombs = clampi(int(length / spacing) + 1, min_bombs, max_bombs)
	var base: float = from.y
	# How far forward of its release a bomb lands from this height and speed,
	# flown in the model the bombs fly.
	var p := Vector3(0.0, base + height, 0.0)
	var v := Vector3(0.0, 0.0, -speed)
	var flown := 0.0
	var t := 0.0
	while p.y > base and t < 60.0:
		v = Ballistics.step(p, v, CarpetBomb.drag_for(payload), 1.0 / 120.0, flown)
		p += v / 120.0
		flown += v.length() / 120.0
		t += 1.0 / 120.0
	var lead: float = -p.z
	_start = from - _dir * (lead + run_in)
	_start.y = base + height
	for i in bombs:
		var s: float = length * float(i) / float(maxi(bombs - 1, 1))
		_drops.append(run_in + s)
	_end = run_in + lead + length + run_in
	eta = (run_in + lead) / speed
	add_child(_airframe())
	if wing != Vector3.ZERO:
		var w2: Node3D = _airframe()
		w2.position = wing
		add_child(w2)
	global_position = _start
	look_at(_start + _dir, Vector3.UP)
	# put there, not flown there: without this the first frame is drawn
	# part way between the middle of the world and the start of the run
	reset_physics_interpolation()
	Sfx.play_at(get_parent(), "roar", _start, 10.0, 0.8 if spec_id == "b2" else 1.2, 9000.0)

## One of the aircraft flying it, loaded for the job and flying it with the
## doors open and the load showing. The B-2 as it is set out carries a B83
## and a B61 in its bays; a strike jet is set out for air to air.
func _airframe() -> Node3D:
	var spec: Dictionary = JetSpec.get_spec(spec_id).duplicate(true)
	for bay in spec.get("bays", []):
		var st: Array = bay["stations"]
		for i in st.size():
			st[i]["weapon"] = load_weapon
	var m: Dictionary = JetFactory.build(spec)
	var root: Node3D = m["root"]
	for g in m["gear"]:
		(g as Node3D).visible = false
	for bay2 in spec.get("bays", []):
		for d in (m["doors"] as Dictionary).get(bay2["id"], []):
			(d as Node3D).rotation.z = deg_to_rad(float(bay2.get("door_angle", 0.0))) \
				* float((d as Node).get_meta("side", 1.0))
	for k in m["stores"]:
		(m["stores"][k] as Node3D).visible = true
	return root

func _physics_process(delta: float) -> void:
	_along += speed * delta
	global_position = _start + _dir * _along
	while not _drops.is_empty() and _along >= float(_drops[0]):
		_drops.pop_front()
		if payload == "drones":
			# out of the back over the ramp, one after another; each is
			# its own from there on
			var sw := Switchblade.new()
			sw.team = 0
			sw.picture = picture
			sw.arena = arena
			sw.owner_node = arena.player if is_instance_valid(arena) else null
			sw.centre = drone_centre
			sw.slot = _dropped
			get_parent().add_child(sw)
			sw.global_position = global_transform * Vector3(0.0, -2.0, 14.0)
			sw.vel = _dir * speed * 0.35 + Vector3(0, -6.0, 0)
			_dropped += 1
			continue
		var b := CarpetBomb.new()
		b.arena = arena
		b.picture = picture
		b.vel = _dir * speed
		b.cluster = cluster
		b.payload = payload
		b.weapon = load_weapon
		get_parent().add_child(b)
		# every other bomb off the wingman, from where he actually is
		var off := Vector3(0.0, -3.0, 0.0)
		if wing != Vector3.ZERO and _dropped % 2 == 1:
			off += wing
		b.place(global_transform * off)
		_dropped += 1
	if _along >= _end:
		queue_free()

## Seconds until the first bomb lands, and until the run is gone.
func until_first() -> float:
	return maxf((_start.distance_to(from) - _along) / speed, 0.0)

func until_gone() -> float:
	return maxf(_end - _along, 0.0) / speed
