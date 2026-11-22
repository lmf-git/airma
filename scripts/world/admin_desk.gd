class_name AdminDesk
extends RefCounted
## What the admin menu does: putting sets of things into the world (idempotently),
## calling air traffic into the circuit and following it.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World
var traffic: Array[Aircraft] = []

func _init(w: World) -> void:
	world = w

## Air traffic: put an aeroplane in the circuit and let its own pilot fly it.
## Put a set of things into the world, in whatever mission is running, and do
## it idempotently: what is already there is counted first and only the
## shortfall is spawned. Asking twice tops the set up; it does not lay down a
## second one on top of the first.
func populate(what: String) -> void:
	match what:
		"garage":
			var want := ["m1a2", "t90", "type99", "m109", "msta", "m270", "bm30",
				"humvee", "jackal", "vbl", "bradley", "shilka", "patriot"]
			var have := {}
			for v in world.get_tree().get_nodes_in_group("vehicles"):
				if is_instance_valid(v) and v is Tank:
					have[(v as Tank).kind] = true
			var n := 0
			var b: Vector3 = world.base.global_position if is_instance_valid(world.base) \
				else Vector3.ZERO
			for k in want:
				if have.has(k):
					continue
				world._spawn_tank(Vector3(b.x + 196.0, 0.0, b.z - 424.0 - float(n) * 16.0),
					deg_to_rad(-90.0), 0, k)
				n += 1
			Sim.report("vehicle park: %d added, %d already there" % [n,
				want.size() - n], Sim.Ev.INFO)
		"parked":
			var rows := ["f22", "f35", "f16", "f15", "a10", "fa18", "mq9"]
			var here := {}
			for pjt in world.get_tree().get_nodes_in_group("parked"):
				if is_instance_valid(pjt) and "spec" in pjt:
					here[String(pjt.spec.get("name", ""))] = true
			var m := 0
			for i in rows.size():
				var sp := JetSpec.get_spec(rows[i])
				if here.has(String(sp.get("name", ""))):
					continue
				var j: Aircraft
				if JetSpec.is_rotary(rows[i]):
					j = PlayerHeli.new()
				else:
					j = PlayerJet.new()
				j.setup(rows[i])
				j.team = 0
				j.active = false
				j.name = "Parked %s" % rows[i]
				world.add_child(j)
				# Its own row, well west of the vehicle park. At x=150 running
				# from z=-520 this walked straight into the armour parked at
				# x=196 from z=-424 down, and left an aeroplane standing
				# between the launchers with no room to walk up to it.
				j.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
					Vector3(60.0,
						world._apron_y(60.0, -170.0 - float(i) * 46.0)
							+ world._stance(j.spec),
						-170.0 - float(i) * 46.0))
				j.gear_down = true
				j.gear_anim = 1.0
				j.set_canopy(true, true)
				j.add_to_group("boardable")
				j.add_to_group("hittable")
				j.add_to_group("parked")
				world._reset_interp.call_deferred(j)
				m += 1
			Sim.report("flight line: %d added, %d already there" % [m,
				rows.size() - m], Sim.Ev.INFO)
		"choppers":
			var want_h := 2
			var up_h := 0
			for h0 in world.get_tree().get_nodes_in_group("bandits"):
				if is_instance_valid(h0) and h0 is AIHeli:
					up_h += 1
			var rotary := ["mi28", "z10"]
			var org_h: Vector3 = world.player.global_position if is_instance_valid(world.player) \
				else Vector3.ZERO
			var add_h := 0
			for i in maxi(want_h - up_h, 0):
				var h := AIHeli.new()
				h.setup(rotary[i % rotary.size()])
				h.team = 1
				h.name = "Gunship %d" % (i + 1)
				h.home = org_h + Vector3(-1200.0 + float(i) * 2400.0, 0.0, -5200.0)
				world.add_child(h)
				var hx: float = h.home.x
				var hz: float = h.home.z + 400.0
				h.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)),
					Vector3(hx, Sim.height_at(hx, hz) + 260.0, hz))
				world._reset_interp.call_deferred(h)
				add_h += 1
			Sim.report("hostile helicopters: %d added, %d already up" % [add_h, up_h],
				Sim.Ev.INFO)
		"warships":
			var want_s := 3
			var up_s := 0
			for s0 in world.get_tree().get_nodes_in_group("ships"):
				if is_instance_valid(s0) and (s0 as Ship).team != 0:
					up_s += 1
			var hulls := ["corvette", "type052d", "moudge"]
			var add_s := 0
			for i in maxi(want_s - up_s, 0):
				var sv2 := Ship.new()
				sv2.setup(hulls[i % hulls.size()], 1)
				sv2.ai = true
				world.add_child(sv2)
				var sea2 := world.fleet_yard.deep_water(Vector3(30000.0 + float(i) * 2600.0, 0.0,
					-4000.0 + float(i) * 3000.0))
				sv2.global_position = Vector3(sea2.x, Sim.sea_surface(sea2.x, sea2.z), sea2.z)
				add_s += 1
			Sim.report("hostile shipping: %d added, %d already at sea" % [add_s, up_s],
				Sim.Ev.INFO)
		"bandits":
			var want_up := 4
			var up: int = Sim.census("bandits")
			var added := 0
			var pick := ["su57", "su35", "mig29", "j20"]
			var org: Vector3 = world.player.global_position if is_instance_valid(world.player) \
				else Vector3.ZERO
			for i in maxi(want_up - up, 0):
				var b2 := AIPlane.new()
				b2.setup(pick[i % pick.size()])
				b2.team = 1
				b2.role = "fighter"
				world.add_child(b2)
				var a4 := TAU * float(i) / float(want_up)
				b2.global_position = org + Vector3(cos(a4) * 12000.0, 1800.0,
					sin(a4) * 12000.0)
				b2.linear_velocity = -b2.global_transform.basis.z * 220.0
				world._reset_interp.call_deferred(b2)
				added += 1
			Sim.report("hostile aircraft: %d added, %d already up" % [added, up],
				Sim.Ev.INFO)
		"sats":
			if Sim.census("satellites") > 0:
				Sim.report("satellites: %d already in orbit" %
					Sim.census("satellites"), Sim.Ev.INFO)
			else:
				world.country_bases.launch_constellation()

func do_admin(id: String) -> void:
	match id:
		"type":
			return
		"land":
			call_traffic(world.admin.jet_id, "land", 0)
		"flight":
			for i in 3:
				call_traffic(world.admin.jet_id, "land", i)
		"takeoff":
			call_traffic(world.admin.jet_id, "takeoff", 0)
		"follow":
			world.admin.following = not world.admin.following
			follow_traffic(world.admin.following)
		"add_garage":
			populate("garage")
		"add_parked":
			populate("parked")
		"add_bandits":
			populate("bandits")
		"add_choppers":
			populate("choppers")
		"add_ships":
			populate("warships")
		"add_sats":
			populate("sats")
		"clear":
			for t in traffic:
				if is_instance_valid(t):
					t.queue_free()
			traffic.clear()
			if is_instance_valid(world.cam) and is_instance_valid(world.player):
				world.cam.subject = world.player
	traffic = traffic.filter(func(t): return is_instance_valid(t))
	world.admin.traffic = traffic.size()

func call_traffic(id: String, what: String, slot: int) -> void:
	var craft: Aircraft
	if JetSpec.is_rotary(id):
		craft = PlayerHeli.new()
	else:
		craft = PlayerJet.new()
	craft.setup(id)
	craft.team = 0
	craft.name = "Traffic %d" % (traffic.size() + 1)
	craft.assist = true
	world.add_child(craft)
	var stance := world._stance(craft.spec)
	if what == "takeoff":
		craft.global_transform = Transform3D(Basis(), Vector3(0.0,
			world._apron_y(0.0, 1340.0 - float(slot) * 90.0) + stance + 0.02,
			1340.0 - float(slot) * 90.0))
		craft.gear_down = true
		craft.gear_anim = 1.0
		craft.flaps = 1.0
		craft.flap_anim = 1.0
	else:
		# spaced down the approach so a flight arrives in trail
		var z: float = Airbase.AIM_Z + 12000.0 + float(slot) * 2600.0
		craft.global_transform = Transform3D(Basis(),
			Vector3(140.0, world._apron_y(140.0, z) + 640.0 + slot * 60.0, z))
		craft.rotation = Vector3(deg_to_rad(-3.0), deg_to_rad(-1.2), 0.0)
		var entry := 140.0
		if craft.has_method("ref_speed_kt"):
			entry = float(craft.call("ref_speed_kt")) / 1.94384 * 1.35
		craft.linear_velocity = -craft.global_transform.basis.z * entry
		craft.gear_down = true
		craft.gear_anim = 1.0
		craft.flaps = 1.0
	craft.auto = what
	craft.add_to_group("hittable")
	world._reset_interp.call_deferred(craft)
	traffic.append(craft)
	if world.admin.following:
		follow_traffic(true)
	Sim.report("%s called in: %s" % [String(craft.spec["name"]), what], Sim.Ev.INFO)

## Watch the traffic, from whatever the player happens to be crewing.
##
## Setting the chase camera's subject is not enough on its own. A player on a
## ship or in a tank is looking through *that* vehicle's camera, so the aircraft
## camera can be pointed at a landing aeroplane all it likes and the view never
## moves — which reads as the traffic not flying at all, rather than as the
## camera being somewhere else.
func follow_traffic(on: bool) -> void:
	if not is_instance_valid(world.cam):
		return
	if on:
		var subject: Node3D = null
		for t in traffic:
			if is_instance_valid(t):
				subject = t
				break
		if subject == null:
			world.admin.following = false
			Sim.report("nothing in the circuit to follow", Sim.Ev.BAD)
			return
		world.cam.subject = subject as Aircraft
		world.cam.mode = ChaseCamera.Mode.CHASE
		world.cam.current = true          # take the view off the ship or the tank
		Sim.report("following %s" % subject.name, Sim.Ev.INFO)
		return
	world.cam.subject = world.player if is_instance_valid(world.player) else null
	# and give it back to whatever the player is actually riding
	if is_instance_valid(world.ship) and world.ship.occupied:
		world.ship.cam.current = true
	elif is_instance_valid(world.tank) and is_instance_valid(world.tank.cam):
		world.tank.cam.current = true
	else:
		world.cam.current = true
