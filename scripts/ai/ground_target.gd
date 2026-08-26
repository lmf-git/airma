class_name GroundTarget
extends Node3D
## Static strike targets. SAM sites shoot back.

var kind := "sam"
var team := 1
var health := 100.0
var alive := true
var _cool := 6.0
var _mesh: Node3D

func setup(k: String) -> void:
	kind = k
	add_to_group("hittable")
	add_to_group("ground_targets")
	health = {"sam": 90.0, "hangar": 260.0, "fuel": 120.0, "radar": 80.0}.get(k, 100.0)
	_build()

func hit_radius() -> float:
	return 9.0

func is_alive() -> bool:
	return alive

func _build() -> void:
	_mesh = Node3D.new()
	add_child(_mesh)
	var st := MeshKit.begin()
	match kind:
		"hangar":
			var rings := []
			for z in [-14.0, 14.0]:
				var r := PackedVector3Array()
				for i in 11:
					var a := PI * float(i) / 10.0
					r.append(Vector3(cos(a) * 13.0, sin(a) * 10.0, z))
				r.append(Vector3(-13.0, 0.0, z))
				rings.append(r)
			MeshKit.loft(st, rings, Vector3(0, 4, 0))
			_mesh.add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.36, 0.38, 0.34), 0.8, 0.1)), "M"))
		"fuel":
			MeshKit.cone(st, 7.0, 7.0, 0.0, 9.0, Vector3.ZERO, 14)
			var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.72, 0.70, 0.62), 0.6, 0.4)), "M")
			mi.rotation_degrees = Vector3(-90, 0, 0)
			_mesh.add_child(mi)
		"radar":
			MeshKit.box(st, Vector3(4, 3, 6), Vector3(0, 1.5, 0))
			MeshKit.box(st, Vector3(0.6, 6, 0.6), Vector3(0, 5, 0))
			MeshKit.box(st, Vector3(7.5, 5.0, 0.4), Vector3(0, 9, 0))
			_mesh.add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.30, 0.33, 0.30), 0.7, 0.3)), "M"))
		_:
			MeshKit.box(st, Vector3(6, 2.4, 8), Vector3(0, 1.2, 0))
			MeshKit.box(st, Vector3(4.6, 2.6, 3.2), Vector3(0, 3.4, -0.6))
			for s in [-1.0, 1.0]:
				MeshKit.cone(st, 0.22, 0.22, -2.2, 2.2, Vector3(s * 1.4, 4.6, 0.4), 6)
			_mesh.add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.28, 0.32, 0.26), 0.75, 0.2)), "M"))

func _physics_process(delta: float) -> void:
	if not alive or kind != "sam":
		return
	_cool -= delta
	if _cool > 0.0:
		return
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n):
			continue
		if not (n is Aircraft) or n.team == team or not n.is_alive():
			continue
		var d: float = global_position.distance_to(n.global_position)
		# A battery will not waste a round on something down in the clutter it
		# cannot hold a lock on. Ninety metres was a floor to stop it shooting
		# at parked aircraft; it takes real terrain-following to be safe now.
		if d < 9000.0 and n.agl > 90.0 and _worth_shooting(n as Node3D, d):
			# A battery cannot shoot at what its radar cannot see. Flying the
			# valley floor to stay behind the ridge line is the whole point of
			# going in low, and without this the site engaged straight through
			# the hill it was standing behind.
			if not Sim.line_of_sight(global_position + Vector3(0, 6.0, 0),
					(n as Node3D).global_position):
				continue
			_cool = 14.0
			var xf := Transform3D(Basis.looking_at((n.global_position - global_position).normalized(), Vector3.UP),
				global_position + Vector3(0, 5.5, 0))
			var m := Missile.new()
			m.launch("aim120", xf, Vector3.ZERO, self, n)
			m.team = team
			get_tree().current_scene.add_child(m)
			Effects.dust(get_tree().current_scene, global_position + Vector3(0, 2, 0), 4.0)
			return

## How well this site can hold a low target. A radar looking down at something
## in the weeds is competing with the ground return behind it, and the further
## away it is the worse that gets.
func _worth_shooting(n: Node3D, d: float) -> bool:
	var agl: float = n.global_position.y - Sim.height_at(n.global_position.x,
		n.global_position.z)
	var need: float = 60.0 + 90.0 * (d / 9000.0) * 6.0
	return agl > need

func take_hit(amount: float, _from: Node = null) -> void:
	if not alive:
		return
	if Sim.net != null and Sim.net.active and not Sim.net.is_host \
			and has_meta("zone_asset"):
		Sim.net.report_ground_damage(self, amount)
		return
	apply_damage(amount)

## The damage itself, with no question of who is allowed to deal it.
func apply_damage(amount: float) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		alive = false
		Effects.explosion(get_tree().current_scene, global_position + Vector3(0, 3, 0), 20.0)
		if _mesh:
			_mesh.queue_free()
		remove_from_group("hittable")
		Sim.score += 150
		Sim.report("%s destroyed" % kind.to_upper(), Sim.Ev.GOOD)
