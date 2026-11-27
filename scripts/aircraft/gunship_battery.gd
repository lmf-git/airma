class_name GunshipBattery
extends RefCounted
## A gunship's side battery: the guns on their trunnions, laying them so the
## round arrives on the mark, each gun's own loader, and firing down the barrel
## that is laid. Split out of `aircraft.gd`; every aircraft has one as
## `battery`, and only one whose spec says `gunship` ever uses it.

var ac: Aircraft

func _init(owner_ac: Aircraft) -> void:
	ac = owner_ac

## Loaders run down every tick, whether or not anything is firing.
func tick(delta: float) -> void:
	for gid in cd:
		cd[gid] = maxf(float(cd[gid]) - delta, 0.0)

## Each gun of a gunship's battery has its own crew and its own loader: the
## time until it can fire again, by gun id. It was the one `gun_cd` for all
## three, so a 105 round put the forty and the twenty-five out of action for
## six seconds as well, and switching guns to keep shooting did nothing.
var cd := {}

## AC-130 style battery: side firing shells lobbed at a designated point.
func gun() -> Dictionary:
	if not ac.spec.get("gunship", false):
		return {}
	for g in ac.spec["guns"]:
		if String(g["id"]) == ac.current_weapon():
			return g
	return ac.spec["guns"][0]

## How far a sponson mount will train: a generous arc off the port beam, which
## is where a gunship's whole business is conducted, and well down.
const BATTERY_AZ := 0.79         # +/- 45 degrees fore and aft of the beam
const BATTERY_EL_LO := -0.09     # a shade above the horizontal
const BATTERY_EL_HI := 1.40      # to eighty degrees below it

## Lay the side battery on a point, and say whether it can actually get there.
##
## The barrels used to be part of the airframe mesh, so they pointed wherever
## they had been modelled and the rounds went wherever the sensor was looking:
## the two had nothing to do with one another. They are on trunnions now, and
## the fire comes out along the barrel -- so if the mount cannot train onto the
## mark, the shot cannot be taken either, which is what banking a gunship into
## its orbit is for.
func train(at: Vector3) -> bool:
	var mounts := _mounts()
	if mounts == null:
		return true
	var ok := true
	for m in mounts.get_children():
		var node := m as Node3D
		if node == null:
			continue
		# in the frame the mount actually hangs in, whatever the model root
		# does to it
		var frame := node.get_parent() as Node3D
		var local: Vector3 = (frame.global_transform.affine_inverse() * at
			if frame != null else ac.global_transform.affine_inverse() * at) - node.position
		if local.length() < 1.0:
			continue
		local = local.normalized()
		var az: float = atan2(local.z, -local.x)
		var el: float = asin(clampf(-local.y, -1.0, 1.0))
		if absf(az) > BATTERY_AZ or el < BATTERY_EL_LO or el > BATTERY_EL_HI:
			ok = false
		node.rotation = Vector3(0.0, clampf(az, -BATTERY_AZ, BATTERY_AZ),
			clampf(el, BATTERY_EL_LO, BATTERY_EL_HI))
	return ok

## Lay the battery so the round arrives on the mark, rather than at it.
##
## `train` points the barrels straight down the sight line, and a gunship
## round does not fly down the sight line. The 105 leaves at 494 m/s, so from
## the orbit it is five seconds in the air: it falls a hundred and twenty metres
## on the way, and it carries the aeroplane's own hundred-odd metres a second
## sideways the whole time -- five hundred metres of it. Laid on the mark, the
## whole battery landed short and well astern of whatever the sensor was
## holding, and an area track was a place the rounds never went.
##
## Solved against the shell as it is actually flown: muzzle speed along the
## bore plus the aeroplane's velocity, and gravity applied the way `GunShell`
## applies it, a physics step at a time. A point track is led by its own
## velocity as well. A handful of iterations converges, because the round is
## several times faster than anything else in the sum.
func lead(aim: Vector3, from: Vector3) -> Vector3:
	var g := gun()
	var v0: float = float(g.get("muzzle", 0.0))
	if v0 <= 1.0:
		return aim
	var vt := _mark_velocity(aim)
	var dt: float = 1.0 / float(maxi(Engine.physics_ticks_per_second, 1))
	var t: float = from.distance_to(aim) / v0
	var d := aim - from
	for i in 10:
		d = aim + vt * t - from - ac.linear_velocity * t \
			+ Vector3.UP * 4.905 * (t * t + t * dt)
		t = d.length() / v0
	# a long way out along the solution, so the mounts -- which lay from
	# their own trunnions, a couple of metres from the muzzle -- read the
	# direction and not the point
	return from + d.normalized() * 100000.0

## The training and elevation the first mount needs for a point, in degrees,
## against its limits. For the harness: "cannot train" says nothing about which
## way it cannot.
func need(aim: Vector3) -> Vector2:
	var mounts := _mounts()
	if mounts == null or mounts.get_child_count() == 0:
		return Vector2.ZERO
	var node := mounts.get_child(0) as Node3D
	var at := lead(aim, _port_centre())
	var local: Vector3 = (mounts.global_transform.affine_inverse() * at - node.position).normalized()
	return Vector2(rad_to_deg(atan2(local.z, -local.x)),
		rad_to_deg(asin(clampf(-local.y, -1.0, 1.0))))

## Lay every mount on the solution for the selected gun. What the sight-follows
## loop and the trigger both call, so the barrels you watch are the ones the
## rounds leave.
func lay(aim: Vector3) -> bool:
	return train(lead(aim, _port_centre()))

## Where a gun fires from: its own ports if it names them (a helicopter's
## chin gun and its rocket pods are not in the same place), else the
## aircraft's.
func _ports_of(g: Dictionary) -> Array:
	if g.has("ports"):
		return g["ports"]
	return ac.spec["shape"].get("gun_ports", [Vector3(-2.4, -0.6, 0.0)])

func _port_centre() -> Vector3:
	var ports: Array = _ports_of(gun())
	var c := Vector3.ZERO
	for q in ports:
		c += q as Vector3
	return ac.global_transform * (c / float(maxi(ports.size(), 1)))

## How fast the mark is moving: a point track's own velocity, nothing for a spot
## on the ground.
func _mark_velocity(aim: Vector3) -> Vector3:
	var pd: Variant = ac.get("pod")
	if pd == null or not is_instance_valid(pd) or int(pd.get("mode")) != SensorPod.POINT:
		return Vector3.ZERO
	var t: Variant = pd.get("tracked")
	if t == null or not is_instance_valid(t) or not (t is Node3D) \
			or (t as Node3D).global_position.distance_to(aim) > 1.0:
		return Vector3.ZERO
	if "linear_velocity" in t:
		return t.get("linear_velocity")
	if (t as Node).has_method("get_velocity"):
		return t.call("get_velocity")
	if "vel" in t:
		return t.get("vel")
	return Vector3.ZERO

## The side battery's mounts. Built inside the model, not on the aeroplane: it
## was looked up as a child of the aeroplane itself, where it is not, so it was
## never found -- the barrels never trained, and every round went down the
## sight line instead of along a barrel.
var _mounts_node: Node3D = null

func _mounts() -> Node3D:
	if _mounts_node != null and is_instance_valid(_mounts_node):
		return _mounts_node
	var root: Variant = ac._model.get("root") if ac._model is Dictionary else null
	if root is Node:
		_mounts_node = (root as Node).find_child("SideGuns", true, false) as Node3D
	return _mounts_node

## Where a given barrel is pointing, in world space. The mount was built along
## its own -X, so that axis rotated into the world is the bore.
func _bore(node: Node3D) -> Vector3:
	return (node.global_transform.basis * Vector3(-1.0, 0.0, 0.0)).normalized()

## The mark a gunship's rockets home on: one, moved to wherever the gunner fires.
var _gun_spot: Node3D = null

func fire(world: Node, aim: Vector3) -> bool:
	var g := gun()
	var gid := String(g.get("id", ""))
	if g.is_empty() or float(cd.get(gid, 0.0)) > 0.0 or not ac.alive:
		return false
	var ports: Array = _ports_of(g)
	var pick: int = randi() % ports.size()
	var muzzle: Vector3 = ac.global_transform * (ports[pick] as Vector3)
	# laid on where the round will meet the mark, from the barrel that fires it
	var lead_pt := lead(aim, muzzle)
	# A rocket steers itself onto the spot: it leaves pointed at it. Laid like a
	# shell -- held up for a fall at its full speed, which it does not reach
	# for a second -- every Hydra off a gunner's pod went out high, overflew
	# the mark and was trying to pull fifty g at the bottom of it with ten to
	# pull with: measured, closest pass eighty-five metres, every round.
	if g.has("missile"):
		lead_pt = muzzle + (aim - muzzle).normalized() * 100000.0
	if not train(lead_pt):
		return false
	# One round, then the loader. This line went missing once and the 105 fired
	# every physics step -- a hundred and twenty howitzer rounds a second.
	cd[gid] = 60.0 / float(g["rpm"])
	# Along the barrel that is actually firing, not along the sight line. The
	# two agree whenever the mount is on the mark, which is the point. With no
	# mount to read it is the solution itself -- it was the sight line, which
	# is exactly where a round does not go.
	var dir := lead_pt - muzzle
	var mounts := _mounts()
	if mounts != null and pick < mounts.get_child_count():
		var node := mounts.get_child(pick) as Node3D
		if node != null:
			dir = _bore(node)
	# Was `dir.length() < 1.0`, written for the hundred-kilometre solution
	# vector. The bore is a unit vector, and a unit vector is 0.99999994 long
	# about as often as it is 1.0: every such shot was refused *after* the
	# loader had been started, so the 105 sat through six seconds for a round
	# that never left, on the mark the whole time.
	if dir.length_squared() < 1e-6:
		cd[gid] = 0.0
		return false
	dir = dir.normalized()
	# A cone round the bore, `spread` radians at its edge. It was a random
	# box of that size on all three axes -- the corners half as wide again,
	# and the part along the bore wasted -- and a gunship looks down at a
	# shallow slant, so the up-and-down half of the error was stretched three
	# times over along the ground.
	var sp: float = g["spread"]
	var a := randf() * TAU
	var r: float = sqrt(randf()) * sp
	var bb := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	dir = (bb * Vector3(cos(a) * r, sin(a) * r, -1.0)).normalized()
	# A rocket from the pods is a rocket: the same round the aircraft fires off
	# its rails, motor, smoke and all, homing on the gunner's mark the way an
	# Apache's are laid by its sight. It was a shell with a rocket's damage --
	# a tracer -- which neither looked nor flew like one.
	if g.has("missile"):
		if not is_instance_valid(_gun_spot):
			_gun_spot = DesignatedSpot.new()
			_gun_spot.team = ac.team
			world.add_child(_gun_spot)
		_gun_spot.global_position = aim
		_gun_spot.set("_life", 140.0)
		var m := Missile.new()
		m.laser_guided = true
		var xf_m := Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT), muzzle)
		m.launch(String(g["missile"]), xf_m, ac.linear_velocity, ac, _gun_spot)
		world.add_child(m)
		ac.store_released.emit(m)
		Sfx.play_at(world, "launch", muzzle, -3.0, randf_range(0.92, 1.06))
		return true
	var shell := GunShell.new()
	shell.vel = dir * float(g["muzzle"]) + ac.linear_velocity
	# laid by `lead`, which allows for gravity and not for the air:
	# kept to that, so what it lays on is where it lands
	shell.drag = 0.0
	shell.damage = float(g["damage"])
	shell.blast = float(g["blast"])
	shell.frag = float(g.get("frag", 0.0))
	shell.shooter = ac
	shell.team = ac.team
	# what it was sent at, so --debugweapons can say how far off it landed
	shell.set_meta("aim", aim)
	shell.set_meta("origin", muzzle)
	world.add_child(shell)
	shell.global_position = muzzle
	# a gunship's shells on every screen: see `NetLaunches.share`
	if Sim.net != null and Sim.net.active:
		Sim.net.launches.share(ac, shell)
	Effects.muzzle_flash(world, muzzle, dir, 2.6 if float(g["rpm"]) < 40.0 else 1.3)
	Effects.dust(world, muzzle, 1.6)
	Sfx.play_at(world, "boom" if float(g["rpm"]) < 40.0 else "rifle", muzzle,
		-2.0 if float(g["rpm"]) < 40.0 else -6.0, 0.55 if float(g["rpm"]) < 40.0 else 0.8, 3000.0)
	return true
