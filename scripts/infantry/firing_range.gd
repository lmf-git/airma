class_name FiringRange
extends Node3D
## A range to try the small arms on. A firing line with every weapon laid out
## on the rack behind it -- F picks one up -- and a lane of boards out to three
## hundred metres. Each board keeps the holes it has been given and says how
## many, and where the last one went from the middle of it, so a group can be
## read without walking out to it. Nothing on it shoots back, and the ammunition
## does not run out.

const DISTANCES := [10.0, 25.0, 50.0, 100.0, 200.0, 300.0]
## How far the boards are walked off the centre line, so that from the firing
## line no board is behind another: worked out by bearing, not by eye. With the
## far board on the centre line the rounds sent at it went into the top of the
## ten metre board in front of it.
const STAGGER := [-3.0, 3.0, -2.0, 4.0, -12.0, 10.0]
const LANE_LEN := 315.0

var world: Node = null
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var targets: Array = []
var _rack: Dictionary = {}       # kit id -> the Drop on the rack, or null
var _rack_at: Dictionary = {}    # kit id -> where it lies
var _tick := 0.0

## Where a range would go out from `centre`: the first bearing and distance
## from which a lane `LANE_LEN` long is clear at chest height all the way.
## Returns [origin, dir], or [] when nowhere round the town will do.
static func site_near(centre: Vector3) -> Array:
	var best: Array = []
	var best_clear := 0.0
	for ring in range(0, 7):
		var r: float = 110.0 + float(ring) * 45.0
		for bi in 16:
			var a: float = TAU * float(bi) / 16.0 + float(ring) * 0.2
			var d := Vector3(cos(a), 0.0, sin(a))
			var p := centre + d * r
			p.y = Sim.height_at(p.x, p.z)
			# standing room at the firing line
			if Obstacles.hit(p + Vector3(0, 1.0, 0), 2.5) >= 0:
				continue
			var eye: Vector3 = p + Vector3(0, 1.5, 0)
			var far: Vector3 = p + d * LANE_LEN
			far.y = Sim.height_at(far.x, far.z) + 1.2
			var look: Vector3 = (far - eye).normalized()
			var clear: float = Firearm.sight_range(eye, look, LANE_LEN + 20.0)
			if clear > best_clear:
				best_clear = clear
				best = [p, d]
			if clear >= LANE_LEN - 2.0:
				return [p, d]
	return best

func setup(owner_world: Node, at: Vector3, facing: Vector3) -> void:
	world = owner_world
	origin = at
	dir = Vector3(facing.x, 0.0, facing.z).normalized()

func _ready() -> void:
	top_level = true
	global_position = Vector3.ZERO
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	_firing_line(right)
	for i in DISTANCES.size():
		var dist: float = DISTANCES[i]
		var p: Vector3 = origin + dir * dist + right * float(STAGGER[i])
		p.y = Sim.height_at(p.x, p.z)
		var t := RangeTarget.new()
		t.distance = dist
		t.facing = -dir
		add_child(t)
		t.global_position = p
		targets.append(t)
	# the rack: every weapon there is, laid out behind the line
	var kits: Array = []
	for k in Firearm.KIT:
		kits.append(String(k["id"]))
	for i in kits.size():
		var along: float = (float(i) - float(kits.size() - 1) * 0.5) * 1.1
		var at: Vector3 = origin - dir * 3.0 + right * along
		_rack_at[kits[i]] = at
		_rack[kits[i]] = null
	_lay_rack()
	Sim.report("FIRING RANGE — boards at 10, 25, 50, 100, 200 and 300 m down the lane in front of you", Sim.Ev.INFO)
	Sim.report("every weapon is on the rack behind the line: F to pick one up. The ammunition does not run out.",
		Sim.Ev.INFO)

## The line itself: a painted stripe across the lane and a bench to rest on,
## and a stake every fifty metres down it so the distance can be read off.
func _firing_line(right: Vector3) -> void:
	var st := MeshKit.begin()
	var bs := Basis(right, Vector3.UP, -dir)
	var xf := Transform3D(bs, origin)
	# stripe
	MeshKit.box(st, Vector3(28.0, 0.03, 0.18), Vector3(0, 0.02, 0))
	var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.86, 0.80, 0.30), 0.9, 0.0)), "FiringLine")
	add_child(mi)
	mi.global_transform = xf
	mi.global_position.y = Sim.height_at(origin.x, origin.z)
	# a bench to rest on, off to the left of where he stands so it is not in
	# his way to the line
	var bst := MeshKit.begin()
	MeshKit.box(bst, Vector3(2.4, 0.06, 0.7), Vector3(-4.5, 0.88, -0.2))
	for sx in [-5.5, -3.5]:
		MeshKit.box(bst, Vector3(0.08, 0.86, 0.6), Vector3(sx, 0.43, -0.2))
	var bench := MeshKit.mi(MeshKit.finish(bst, MeshKit.mat(Color(0.42, 0.30, 0.18), 0.9, 0.0)), "Bench")
	add_child(bench)
	bench.global_transform = xf
	bench.global_position.y = Sim.height_at(origin.x, origin.z)
	for m in range(50, int(LANE_LEN), 50):
		for side in [-1.0, 1.0]:
			var p: Vector3 = origin + dir * float(m) + right * side * 15.0
			p.y = Sim.height_at(p.x, p.z)
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.1, 1.2, 0.1)
			post.mesh = bm
			post.material_override = MeshKit.mat(Color(0.9, 0.9, 0.85), 0.8, 0.0)
			add_child(post)
			post.global_position = p + Vector3(0, 0.6, 0)
			var lb := Label3D.new()
			lb.text = "%d m" % m
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.font_size = 64
			lb.pixel_size = 0.01
			lb.modulate = Color(1.0, 0.95, 0.6)
			add_child(lb)
			lb.global_position = p + Vector3(0, 1.6, 0)

func _lay_rack() -> void:
	for id in _rack:
		var d: Variant = _rack[id]
		if d != null and is_instance_valid(d):
			continue
		var at: Vector3 = _rack_at[id]
		var g: Dictionary = Firearm.spec(String(id))
		var drop := Firearm.Drop.new()
		drop.kit = String(id)
		drop.rounds = int(g["mag"])
		drop.life = 1e9
		world.add_child(drop)
		drop.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
		_rack[id] = drop

func _exit_tree() -> void:
	# the rack belongs to the range, not to the world it was laid out in
	for id in _rack:
		var d: Variant = _rack[id]
		if d != null and is_instance_valid(d):
			(d as Node).queue_free()
	_rack.clear()

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	# whatever was taken off the rack goes back on it
	_lay_rack()
	# and the man on the line never runs dry
	var w: Variant = world.get("walker") if world != null else null
	if w != null and is_instance_valid(w):
		var wk: Walker = w
		var g: Dictionary = wk.gun_spec()
		var full: int = int(g["mag"]) * maxi(int(g.get("spare", 3)), 3)
		if wk.spare < full:
			wk.spare = full
			if wk.kit_idx < wk._spare.size():
				wk._spare[wk.kit_idx] = full
		wk.grenades = maxi(wk.grenades, 2)

## Clear the holes off every board.
func patch_all() -> void:
	for t in targets:
		if is_instance_valid(t):
			(t as RangeTarget).patch()


## One board on a post, facing the line: a man-sized card with the rings on
## it. It takes rounds the way a man does -- through the same test, from the
## round's own path -- and keeps a mark where each one went in.
class RangeTarget extends Node3D:
	const W := 0.60
	const H := 1.00
	const CENTRE_Y := 1.25
	const MAX_HOLES := 60
	var distance := 0.0
	var facing := Vector3.BACK
	var team := 1
	var hits := 0
	var _holes: Array = []
	var _label: Label3D
	var _hole_mesh: Mesh
	var _flash := 0.0
	var _card: MeshInstance3D
	var _card_mat: StandardMaterial3D

	func _ready() -> void:
		add_to_group("hittable")
		add_to_group("range_target")
		look_at(global_position + facing, Vector3.UP)
		# the card faces local +Z, toward the line
		rotate_object_local(Vector3.UP, PI)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.08, CENTRE_Y - H * 0.5 + 0.05, 0.08)
		post.mesh = pm
		post.material_override = MeshKit.mat(Color(0.35, 0.27, 0.18), 0.9, 0.0)
		post.position = Vector3(0, (CENTRE_Y - H * 0.5) * 0.5, -0.06)
		add_child(post)
		_card = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(W, H)
		_card.mesh = qm
		_card_mat = StandardMaterial3D.new()
		_card_mat.albedo_texture = _face()
		_card_mat.roughness = 0.95
		_card.material_override = _card_mat
		_card.position = Vector3(0, CENTRE_Y, 0)
		add_child(_card)
		var back := MeshInstance3D.new()
		var bq := QuadMesh.new()
		bq.size = Vector2(W, H)
		back.mesh = bq
		back.material_override = MeshKit.mat(Color(0.55, 0.45, 0.30), 0.95, 0.0)
		back.position = Vector3(0, CENTRE_Y, -0.01)
		back.rotation = Vector3(0, PI, 0)
		add_child(back)
		var hm := QuadMesh.new()
		hm.size = Vector2(0.022, 0.022)
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.05, 0.05, 0.05)
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.material = hmat
		_hole_mesh = hm
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 48
		_label.pixel_size = 0.004 * clampf(distance / 25.0, 1.0, 9.0)
		_label.outline_size = 8
		_label.position = Vector3(0, CENTRE_Y + H * 0.5 + 0.25 * clampf(distance / 25.0, 1.0, 9.0), 0)
		add_child(_label)
		_say("")

	## The rings, drawn once and shared.
	static var _tex: ImageTexture = null
	static func _face() -> ImageTexture:
		if _tex != null:
			return _tex
		var w := 120
		var h := 200
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		img.fill(Color(0.93, 0.91, 0.84))
		var c := Vector2(w * 0.5, h * 0.5)
		for y in h:
			for x in w:
				var d: float = Vector2(x, y).distance_to(c) / (w * 0.5)
				var col := Color(0.93, 0.91, 0.84)
				if d < 0.25:
					col = Color(0.75, 0.12, 0.10)
				elif d < 0.5:
					col = Color(0.12, 0.12, 0.12) if int(d * 20.0) % 2 == 0 else Color(0.93, 0.91, 0.84)
				elif d < 1.0 and int(d * 10.0) % 2 == 0:
					col = Color(0.20, 0.20, 0.20)
				img.set_pixel(x, y, col)
		_tex = ImageTexture.create_from_image(img)
		return _tex

	func is_alive() -> bool:
		return true

	func hit_radius() -> float:
		return 0.6

	## Where a round's path from `a` to `b` crosses the card: how hard (2 in
	## the red, 1 on the card, 0 a miss) and how far along the path. The same
	## question a soldier is asked, so a target is hit exactly when a man
	## standing there would have been.
	func bullet_hit(a: Vector3, b: Vector3) -> Vector2:
		var inv := _card.global_transform.affine_inverse()
		var la: Vector3 = inv * a
		var lb: Vector3 = inv * b
		if (la.z > 0.0) == (lb.z > 0.0) or absf(lb.z - la.z) < 1e-6:
			return Vector2.ZERO
		var t: float = la.z / (la.z - lb.z)
		var p: Vector3 = la.lerp(lb, t)
		if absf(p.x) > W * 0.5 or absf(p.y) > H * 0.5:
			return Vector2.ZERO
		_mark(p)
		return Vector2(2.0 if Vector2(p.x, p.y).length() < W * 0.125 else 1.0, t)

	func take_hit(_amount: float, _from: Node = null) -> void:
		_flash = 0.25

	func _mark(p: Vector3) -> void:
		hits += 1
		var hole := MeshInstance3D.new()
		hole.mesh = _hole_mesh
		hole.position = Vector3(p.x, p.y, 0.004)
		_card.add_child(hole)
		_holes.append(hole)
		while _holes.size() > MAX_HOLES:
			var old: Node = _holes.pop_front()
			if is_instance_valid(old):
				old.queue_free()
		var cm := Vector2(p.x, p.y) * 100.0
		var lr := "%d cm %s" % [int(absf(cm.x)), "right" if cm.x > 0.0 else "left"] if absf(cm.x) >= 1.0 else "centre"
		var ud := "%d cm %s" % [int(absf(cm.y)), "high" if cm.y > 0.0 else "low"] if absf(cm.y) >= 1.0 else "level"
		_say("last: %s, %s" % [lr, ud])

	func patch() -> void:
		for h in _holes:
			if is_instance_valid(h):
				(h as Node).queue_free()
		_holes.clear()
		hits = 0
		_say("")

	func _say(last: String) -> void:
		_label.text = "%d m   %d hit%s%s" % [int(distance), hits, "" if hits == 1 else "s",
			("\n" + last) if last != "" else ""]

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash -= delta
			_card_mat.albedo_color = Color(1.0, 0.85, 0.6) if _flash > 0.0 else Color.WHITE
