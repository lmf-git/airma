class_name NetLink
extends Node
## LAN multiplayer. Every peer flies its own aircraft locally and broadcasts a
## compact state packet; remote aircraft are shown as interpolated ghosts. The
## host additionally publishes the AI flight and the objective state.

signal roster_changed()

const PORT := 27015
const RATE := 1.0 / 20.0      # state packets per second

var world: Node = null
var active := false
var is_host := false
var my_id := 1
var roster := {}              # peer id -> {jet, name, team}
var ghosts := {}              # peer id -> Aircraft (remote)
var foot_ghosts := {}         # peer id -> Pilot mesh for players on foot
var veh_ghosts := {}          # peer id -> Tank driven by a remote player
var ai_ghosts := {}           # ai index -> Aircraft stand-in on a client
var ai_kinds := {}            # ai index -> airframe id, from the roster
var _acc := 0.0
var _obj_acc := 0.0
var _ai_acc := 0.0
var _gnd_acc := 0.0
var _ai_seen := {}
var _ship_acc := 0.0
var ship_conn := -1           # fleet index this peer has the conn of, -1 none
var verbose := false
var upnp_ready := false           # the router forwarded the port
var upnp_external := ""           # the address other people should use
var _upnp: UPNP = null
var _upnp_thread: Thread = null
var tx := 0

var rx := 0
var status := "offline"

# --------------------------------------------------------------------------
func host(jet_id: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err != OK:
		status = "host failed (%d)" % err
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	active = true
	is_host = true
	my_id = 1
	roster[1] = {"jet": jet_id, "name": "Host", "team": 0}
	status = "hosting on port %d" % PORT
	Sim.report("Hosting on port %d — others can join by IP." % PORT, Sim.Ev.GOOD)
	_open_port()
	roster_changed.emit()
	return true

## Ask the router to forward the port so somebody outside the house can actually
## reach the game. Discovery talks to the network and takes seconds, so it runs
## on its own thread: doing it inline froze the frame the match started on.
func _open_port() -> void:
	if _upnp_thread != null:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)

func _upnp_worker() -> void:
	var up := UPNP.new()
	var disc := up.discover()
	if disc != UPNP.UPNP_RESULT_SUCCESS:
		_upnp_done.call_deferred(false, "", "no router answered (%d)" % disc)
		return
	var gw := up.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		_upnp_done.call_deferred(false, "", "router does not do UPnP")
		return
	# ENet is UDP; map TCP too so a future lobby or query port works
	var r1 := up.add_port_mapping(PORT, PORT, "flight sim", "UDP", 0)
	up.add_port_mapping(PORT, PORT, "flight sim", "TCP", 0)
	if r1 != UPNP.UPNP_RESULT_SUCCESS:
		_upnp_done.call_deferred(false, "", "router refused the mapping (%d)" % r1)
		return
	_upnp = up
	_upnp_done.call_deferred(true, up.query_external_address(), "")

func _upnp_done(ok: bool, ip: String, why: String) -> void:
	upnp_ready = ok
	upnp_external = ip
	if ok:
		status = "hosting on %s:%d" % [ip, PORT]
		Sim.report("Port forwarded — others can join at %s" % ip, Sim.Ev.GOOD)
	else:
		Sim.report("No port forwarding: %s. Players on your own network can " % why
			+ "still join by local IP.", Sim.Ev.INFO)
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	_upnp_thread = null

## Hand the port back when the match ends, so it is not left open.
func _close_port() -> void:
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp.delete_port_mapping(PORT, "TCP")
		_upnp = null
	upnp_ready = false
	upnp_external = ""

func join(address: String, jet_id: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		status = "join failed (%d)" % err
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected.bind(jet_id))
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_dropped)
	active = true
	is_host = false
	status = "connecting to %s" % address
	Sim.report("Connecting to %s..." % address, Sim.Ev.INFO)
	return true

func leave() -> void:
	_close_port()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	for id in ghosts:
		if is_instance_valid(ghosts[id]):
			ghosts[id].queue_free()
	for id in foot_ghosts:
		if is_instance_valid(foot_ghosts[id]):
			foot_ghosts[id].queue_free()
	for id in veh_ghosts:
		if is_instance_valid(veh_ghosts[id]):
			veh_ghosts[id].queue_free()
	for id in ai_ghosts:
		if is_instance_valid(ai_ghosts[id]):
			ai_ghosts[id].queue_free()
	ai_ghosts.clear()
	set_fleet_ghosts(false)
	ship_conn = -1
	ai_kinds.clear()
	_ai_seen.clear()
	veh_ghosts.clear()
	foot_ghosts.clear()
	ghosts.clear()
	roster.clear()
	active = false
	is_host = false
	status = "offline"
	roster_changed.emit()

# --------------------------------------------------------------------------
func _on_peer_joined(id: int) -> void:
	Sim.report("player %d joined" % id, Sim.Ev.GOOD)
	# tell the newcomer what we are playing, then hand over the roster
	rpc_id(id, "net_mission", String(Sim.mission))
	for pid in roster:
		rpc_id(id, "net_announce", pid, roster[pid]["jet"], roster[pid]["team"])
	# the AI roster was announced to whoever was connected at the time, so
	# forget it and let the next publish describe the whole set again
	_ai_seen.clear()

func _on_peer_left(id: int) -> void:
	Sim.report("player %d left" % id, Sim.Ev.BAD)
	if ghosts.has(id) and is_instance_valid(ghosts[id]):
		ghosts[id].queue_free()
	ghosts.erase(id)
	roster.erase(id)
	roster_changed.emit()

func _on_connected(jet_id: String) -> void:
	my_id = multiplayer.get_unique_id()
	status = "connected as %d" % my_id
	Sim.report("Connected as player %d" % my_id, Sim.Ev.GOOD)
	if verbose:
		print("[net] announcing self %d to server" % my_id)
	rpc("net_announce", my_id, jet_id, 0)
	net_announce(my_id, jet_id, 0)
	set_fleet_ghosts(true)

func _on_failed() -> void:
	status = "connection failed"
	Sim.report("Connection failed", Sim.Ev.BAD)
	active = false

func _on_dropped() -> void:
	status = "host closed"
	Sim.report("Host closed the session", Sim.Ev.BAD)
	leave()

# --------------------------------------------------------------------------
## The host decides the match; a joiner restarts into the same one so its zones
## and objectives exist locally for the state updates to land on.
@rpc("authority", "call_remote", "reliable")
func net_mission(mission: String) -> void:
	if is_host or world == null:
		return
	if String(Sim.mission) == mission:
		return
	Sim.report("host is running %s" % mission, Sim.Ev.INFO)
	world.call_deferred("_start", String(Sim.selected_jet), mission)

## Objective state is authoritative on the host: sector ownership, capture
## progress and the ticket counts are pushed rather than simulated twice.
@rpc("authority", "call_remote", "unreliable_ordered")
func net_objectives(labels: PackedStringArray, owners: PackedInt32Array,
		progress: PackedFloat32Array, alive_mask: PackedInt32Array,
		t_us: int, t_them: int) -> void:
	if is_host or world == null:
		return
	var mode = world.get("mode")
	if mode == null or not is_instance_valid(mode):
		return
	mode.tickets[0] = t_us
	mode.tickets[1] = t_them
	for z in world.get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		var idx := labels.find(String(z.label))
		if idx < 0:
			continue
		z.owner_team = owners[idx]
		z.progress = progress[idx]
		# Whatever the host says has been destroyed is destroyed here too, so
		# nobody is left shooting at a hangar that fell over minutes ago.
		var mask: int = alive_mask[idx]
		for i in z.assets.size():
			var a = z.assets[i]
			if not is_instance_valid(a) or not a.has_method("apply_damage"):
				continue
			if (mask & (1 << i)) == 0 and bool(a.get("alive")):
				a.apply_damage(1.0e6)

@rpc("any_peer", "call_remote", "reliable")
func net_announce(id: int, jet_id: String, team: int) -> void:
	roster[id] = {"jet": jet_id, "name": "P%d" % id, "team": team}
	if verbose:
		print("[net] announce id=%d jet=%s from=%d roster=%d" % [
			id, jet_id, multiplayer.get_remote_sender_id(), roster.size()])
	if id != my_id and not ghosts.has(id):
		_make_ghost(id, jet_id, team)
	if is_host and id != 1:
		# relay to everyone else
		rpc("net_announce", id, jet_id, team)
	roster_changed.emit()

func _make_ghost(id: int, jet_id: String, team: int) -> void:
	if world == null:
		return
	var g := Aircraft.new()
	g.setup(jet_id)
	g.team = team
	g.name = "Player %d" % id
	g.make_ghost()
	g.alive = true
	g.add_to_group("remote")
	g.set_meta("net_id", id)
	# Deliberately NOT hittable and not visible yet. Until the first state
	# packet lands we have no idea where this aircraft is, and a placeholder
	# sitting over the airfield gets shot to pieces by anything nearby --
	# which, now that damage is authoritative, kills the real one too.
	g.visible = false
	world.add_child(g)
	g.global_position = Vector3(0, 3000, 0)
	ghosts[id] = g

## Packed state: position, orientation, velocity and the animation flags.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_state(id: int, pos: Vector3, rot: Quaternion, vel: Vector3, thr: float, flags: int) -> void:
	rx += 1
	var g: Aircraft = ghosts.get(id)
	if g == null or not is_instance_valid(g):
		return
	if not g.has_meta("t_rx"):
		g.global_position = pos            # first fix: appear where it actually is
		g.visible = true
		g.add_to_group("hittable")
	g.set_meta("target_pos", pos)
	g.set_meta("t_rx", Time.get_ticks_msec())
	g.set_meta("target_rot", rot)
	# A frozen kinematic body has its linear_velocity recomputed by the physics
	# server from however far we teleported it last tick, so the value we assign
	# does not survive. Keep the reported one where nothing else can touch it:
	# reading the derived one back and dead reckoning along it is a feedback
	# loop, and it threw ghosts to 20 km and beyond.
	g.set_meta("net_vel", vel)
	g.linear_velocity = vel
	g.throttle = thr
	g.power = thr
	if (flags & 16) != 0:
		if g.alive:
			g.alive = false
			Effects.explosion(world, g.global_position, 12.0)
	g.gear_down = bool(flags & 1)
	g.hook_down = bool(flags & 2)
	g.flaps = 1.0 if (flags & 4) else 0.0
	if (flags & 8) != 0:
		g.set_bays(true)
	else:
		g.set_bays(false)
	if is_host:
		rpc("net_state", id, pos, rot, vel, thr, flags)

## On-foot players, including anyone riding in someone else's cargo hold. The
## hold owner is sent as a peer id so the passenger stays attached to the right
## aircraft on every machine instead of drifting in world space.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_foot(id: int, pos: Vector3, yaw: float, crouch: bool, in_hold_of: int) -> void:
	var g: Node3D = foot_ghosts.get(id)
	if g == null or not is_instance_valid(g):
		var pil := Pilot.new()
		pil.build()
		pil.name = "Crew %d" % id
		world.add_child(pil)
		foot_ghosts[id] = pil
		g = pil
	var want_parent: Node = world
	if in_hold_of != 0:
		var carrier_jet: Aircraft = ghosts.get(in_hold_of)
		if in_hold_of == my_id and world.get("player") != null:
			carrier_jet = world.get("player")
		if carrier_jet and is_instance_valid(carrier_jet) and carrier_jet.has_hold():
			want_parent = carrier_jet.hold_node()
	if g.get_parent() != want_parent:
		var keep := g.global_transform
		g.get_parent().remove_child(g)
		want_parent.add_child(g)
		g.global_transform = keep
	g.position = pos
	g.rotation.y = yaw
	if g is Pilot:
		if crouch:
			(g as Pilot).pose_crouch(0.0, false)
		else:
			(g as Pilot).pose_idle()
	if is_host:
		rpc("net_foot", id, pos, yaw, crouch, in_hold_of)

## Only the host simulates the AI. Clients are told what exists and where it
## is, so every player in a co-op match is fighting the same aircraft rather
## than a private copy that has already diverged.
@rpc("authority", "call_remote", "reliable")
func net_ai_roster(idx: PackedInt32Array, kinds: PackedStringArray,
		teams: PackedInt32Array) -> void:
	if is_host or world == null:
		return
	for i in idx.size():
		var key := idx[i]
		ai_kinds[key] = kinds[i]
		if ai_ghosts.has(key) and is_instance_valid(ai_ghosts[key]):
			continue
		var g := Aircraft.new()
		g.setup(kinds[i])
		g.team = teams[i]
		g.name = "AI %d" % key
		g.make_ghost()
		g.add_to_group("remote")
		g.add_to_group("bandits")
		g.set_meta("net_ai", key)
		g.visible = false
		world.add_child(g)
		g.global_position = Vector3(0, 3000, 0)
		ai_ghosts[key] = g

@rpc("authority", "call_remote", "unreliable_ordered")
func net_ai_state(idx: PackedInt32Array, pos: PackedVector3Array,
		rot: PackedFloat32Array, vel: PackedVector3Array, alive: PackedByteArray) -> void:
	if is_host or world == null:
		return
	for i in idx.size():
		var g: Aircraft = ai_ghosts.get(idx[i])
		if g == null or not is_instance_valid(g):
			continue
		if alive[i] == 0:
			if g.alive:
				g.alive = false
				g.visible = false
				Effects.explosion(world, g.global_position, 12.0)
			continue
		if not g.has_meta("t_rx"):
			g.global_position = pos[i]     # first fix: snap, do not fly in from the spawn
			g.visible = true
			g.add_to_group("hittable")
		g.set_meta("target_pos", pos[i])
		g.set_meta("t_rx", Time.get_ticks_msec())
		g.set_meta("target_rot", Quaternion(Vector3.UP, rot[i * 2]) \
			* Quaternion(Vector3.RIGHT, rot[i * 2 + 1]))
		g.set_meta("net_vel", vel[i])
		g.linear_velocity = vel[i]

@rpc("authority", "call_remote", "reliable")
func net_ai_gone(idx: PackedInt32Array) -> void:
	if is_host or world == null:
		return
	for key in idx:
		var g: Aircraft = ai_ghosts.get(key)
		ai_ghosts.erase(key)
		ai_kinds.erase(key)
		if g != null and is_instance_valid(g):
			if verbose:
				print("[net] ai %d removed by the host" % key)
			if g.visible:
				Effects.explosion(world, g.global_position, 12.0)
			g.queue_free()

# ----------------------------------------------------------------- chat
## Text chat. Anyone may send; it goes to everybody including the sender, so
## one code path posts the line and the local echo cannot drift from what the
## rest of the session sees.
@rpc("any_peer", "call_local", "reliable")
func net_chat(who: String, text: String, team: int) -> void:
	if world == null:
		return
	var box = world.get("chat")
	if box != null and is_instance_valid(box):
		box.post(who, text.substr(0, 140), team)

func say(text: String) -> void:
	if not active:
		return
	var who := "P%d" % my_id
	var team := 0
	if roster.has(my_id):
		who = String(roster[my_id].get("name", who))
		team = int(roster[my_id].get("team", 0))
	rpc("net_chat", who, text.substr(0, 140), team)

# ---------------------------------------------------------------- ships
## Ships do not need a spawn roster. Every peer builds the same fleet from the
## same plan at load, so a hull is addressed by its index in that plan and the
## host only has to say where it is and what state it is in. Clients hold theirs
## as ghosts: posed, not simulated, so the two ends cannot diverge.
## A client hands the whole fleet over to the host. They are built identically
## on both ends at load, long before anyone connects, so this flips them rather
## than trying to decide at construction time.
func set_fleet_ghosts(on: bool) -> void:
	if world == null:
		return
	for n in world.get_tree().get_nodes_in_group("ships"):
		if is_instance_valid(n) and n is Ship:
			(n as Ship).ghost = on

func _ship_by_index(i: int) -> Ship:
	if world == null:
		return null
	for n in world.get_tree().get_nodes_in_group("ships"):
		if is_instance_valid(n) and n is Ship and (n as Ship).fleet_idx == i:
			return n as Ship
	return null

@rpc("authority", "call_remote", "unreliable_ordered")
func net_ships(idx: PackedInt32Array, pos: PackedVector3Array,
		yaw: PackedFloat32Array, hp: PackedFloat32Array,
		dmg: PackedFloat32Array, flags: PackedInt32Array) -> void:
	if is_host or world == null:
		return
	rx += 1
	for i in idx.size():
		var sh := _ship_by_index(idx[i])
		if sh == null:
			continue
		sh.net_apply(pos[i], yaw[i], hp[i], dmg[i * 3], dmg[i * 3 + 1],
			dmg[i * 3 + 2], flags[i])

## The conn changes hands. The host stops letting the AI captain steer that
## hull and starts taking its wheel and telegraph from the peer instead.
@rpc("any_peer", "call_local", "reliable")
func net_ship_conn(i: int, taken: bool) -> void:
	if not is_host:
		return
	var sh := _ship_by_index(i)
	if sh == null or not sh.alive:
		return
	var who := multiplayer.get_remote_sender_id()
	if taken:
		if sh.remote_conn != 0 and sh.remote_conn != who:
			return                      # somebody already has her
		sh.remote_conn = who
		sh.ai = false
	elif sh.remote_conn == who:
		sh.remote_conn = 0
		sh.ai = true

@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_ship_orders(i: int, helm: float, telegraph: float,
		yaw: float, pitch: float) -> void:
	if not is_host:
		return
	var sh := _ship_by_index(i)
	if sh == null or sh.remote_conn != multiplayer.get_remote_sender_id():
		return
	sh.net_orders(helm, telegraph, yaw, pitch)

## A request to shoot, and the round everyone else sees. `what` is 0 for the
## main battery and 1 for the tubes.
@rpc("any_peer", "call_remote", "reliable")
func net_ship_fire(i: int, what: int, yaw: float, pitch: float) -> void:
	if not is_host:
		return
	var sh := _ship_by_index(i)
	if sh == null or not sh.alive:
		return
	if sh.remote_conn != multiplayer.get_remote_sender_id():
		return
	sh.aim_yaw = yaw
	sh.aim_pitch = pitch
	if what == 1:
		sh.fire_vls()
	else:
		sh.fire_gun()

## The host telling everyone a ship's battery went off, so the flash and the
## tracer are on every screen and not only on the hull that fired.
@rpc("authority", "call_remote", "reliable")
func net_ship_shot(i: int, yaw: float, pitch: float) -> void:
	if is_host or world == null:
		return
	var sh := _ship_by_index(i)
	if sh == null:
		return
	sh.show_shot(yaw, pitch)

func request_ship_fire(i: int, what: int, yaw: float, pitch: float) -> void:
	if not active or i < 0:
		return
	rpc_id(1, "net_ship_fire", i, what, yaw, pitch)

func take_ship_conn(i: int, taken: bool) -> void:
	if not active:
		return
	ship_conn = i if taken else -1
	if is_host:
		var sh := _ship_by_index(i)
		if sh != null:
			sh.remote_conn = 0
			sh.ai = not taken
		return
	rpc_id(1, "net_ship_conn", i, taken)

@rpc("any_peer", "call_remote", "reliable")
func net_ship_hit(i: int, amount: float) -> void:
	if not is_host:
		return
	var sh := _ship_by_index(i)
	if sh != null and sh.alive:
		sh.take_hit(amount, null)

## A client's weapon reached a hull the host owns. The client's copy is a
## picture and has no standing to decide whether it just sank.
func report_ship_damage(sh: Node, amount: float) -> void:
	if not active or not (sh is Ship):
		return
	var i: int = (sh as Ship).fleet_idx
	if i < 0:
		return
	if is_host:
		(sh as Ship).take_hit(amount, null)
	else:
		rpc_id(1, "net_ship_hit", i, amount)

## Host side: one packet for the whole fleet, five times a second. A ship is
## slow and there are a dozen of them, so this is cheaper than treating each
## hull as its own replicated actor.
func _publish_ships() -> void:
	var idx := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var hp := PackedFloat32Array()
	var dmg := PackedFloat32Array()
	var flags := PackedInt32Array()
	for n in world.get_tree().get_nodes_in_group("ships"):
		if not is_instance_valid(n) or not (n is Ship):
			continue
		var sh := n as Ship
		if sh.fleet_idx < 0:
			continue
		idx.append(sh.fleet_idx)
		pos.append(sh.global_position)
		yaw.append(sh.heading)
		hp.append(sh.health)
		dmg.append(sh.flood)
		dmg.append(sh.fires)
		dmg.append(sh.list_side)
		var f := 0
		if sh.alive:
			f |= 1
		if sh.is_sinking():
			f |= 2
			f |= int(clampf(sh.sink_fraction(), 0.0, 1.0) * 255.0) << 8
		flags.append(f)
	if idx.size() > 0:
		tx += 1
		rpc("net_ships", idx, pos, yaw, hp, dmg, flags)

## Ground vehicles replicate the same way as aircraft: a kinematic stand-in
## eased onto the last reported pose on the physics tick.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_vehicle(id: int, pos: Vector3, rot: Quaternion, vel: Vector3, turret: float,
		barrel: float) -> void:
	var t: Tank = veh_ghosts.get(id)
	if t == null or not is_instance_valid(t):
		t = Tank.new()
		t.setup(int(roster.get(id, {}).get("team", 1)))
		t.name = "Armour %d" % id
		t.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		t.freeze = true
		t.gravity_scale = 0.0
		t.remove_from_group("boardable")
		t.set_meta("net_id", id)
		world.add_child(t)
		veh_ghosts[id] = t
	t.set_meta("target_pos", pos)
	t.set_meta("t_rx", Time.get_ticks_msec())
	t.set_meta("target_rot", rot)
	t.set_meta("net_vel", vel)
	t.linear_velocity = vel
	t.turret_yaw = turret
	t.turret_pitch = barrel
	if is_host:
		rpc("net_vehicle", id, pos, rot, vel, turret, barrel)

@rpc("any_peer", "call_remote", "reliable")
func net_fire(id: int, weapon: String, origin: Vector3, basis_q: Quaternion, vel: Vector3) -> void:
	if world == null:
		return
	var m := Missile.new()
	var xf := Transform3D(Basis(basis_q), origin)
	var shooter: Node = ghosts.get(id)
	m.launch(weapon, xf, vel, shooter if shooter else self, null)
	world.add_child(m)
	if is_host:
		rpc("net_fire", id, weapon, origin, basis_q, vel)

@rpc("any_peer", "call_remote", "reliable")
func net_hit(target_id: int, amount: float) -> void:
	if target_id == my_id:
		var p = world.get("player") if world else null
		if p and is_instance_valid(p) and p.has_method("take_hit"):
			p.take_hit(amount)
		return
	# not ours to apply: pass it along to the peer that owns that aircraft
	if is_host:
		rpc_id(target_id, "net_hit", target_id, amount)

## A client scored a hit on an AI the host is simulating.
@rpc("any_peer", "call_remote", "reliable")
func net_ai_hit(key: int, amount: float) -> void:
	if is_host:
		_apply_ai_hit(key, amount)

func _apply_ai_hit(key: int, amount: float) -> void:
	for n in world.get_tree().get_nodes_in_group("bandits"):
		if is_instance_valid(n) and not n.is_in_group("remote") \
				and n.get_instance_id() % 100000 == key:
			n.take_hit(amount)
			if verbose:
				print("[net] ai %d took %.0f from a client, hp=%s alive=%s" % [
					key, amount, str(n.get("health")), str(n.is_alive())])
			return

## Garrison armour drives itself, so unlike a structure its pose has to be
## replicated or a client ends up aiming at where its own copy wandered off to.
## The sector label and slot number are enough to address it: both ends built
## the same garrison in the same order.
func _publish_ground() -> void:
	var labels := PackedStringArray()
	var slots := PackedInt32Array()
	var pos := PackedVector3Array()
	var rot := PackedFloat32Array()
	for z in world.get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		for i in z.assets.size():
			var a = z.assets[i]
			if not is_instance_valid(a) or not (a is Tank) or not a.alive:
				continue
			labels.append(String(z.label))
			slots.append(i)
			pos.append(a.global_position)
			rot.append(a.rotation.y)
			rot.append(a.turret_yaw)
			rot.append(a.turret_pitch)
	if labels.size() > 0:
		rpc("net_ground", labels, slots, pos, rot)

@rpc("authority", "call_remote", "unreliable_ordered")
func net_ground(labels: PackedStringArray, slots: PackedInt32Array,
		pos: PackedVector3Array, rot: PackedFloat32Array) -> void:
	if is_host or world == null:
		return
	for z in world.get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		var zl := String(z.label)
		for i in labels.size():
			if labels[i] != zl:
				continue
			var idx := slots[i]
			if idx < 0 or idx >= z.assets.size():
				continue
			var a = z.assets[idx]
			if not is_instance_valid(a) or not (a is Tank):
				continue
			if not a.has_meta("t_rx"):
				# hand the vehicle over to the network: it stops driving and
				# stops falling, and is moved on the physics tick like any ghost
				a.ai = false
				a.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				a.freeze = true
				a.gravity_scale = 0.0
				a.global_position = pos[i]
			a.set_meta("t_rx", Time.get_ticks_msec())
			a.set_meta("gnd_pos", pos[i])
			a.set_meta("gnd_rot", rot[i * 3])
			a.turret_yaw = rot[i * 3 + 1]
			a.turret_pitch = rot[i * 3 + 2]

## Damage that landed on a vehicle or structure somebody else owns.
func report_ground_damage(n: Node, amount: float) -> void:
	if not active:
		return
	if n.has_meta("zone_asset"):
		var k: Array = n.get_meta("zone_asset")
		if verbose:
			print("[net] reporting %.0f damage on %s asset %d to the host" % [
				amount, str(k[0]), int(k[1])])
		rpc_id(1, "net_asset_hit", String(k[0]), int(k[1]), amount)
		return
	if n.has_meta("net_id"):
		var pid := int(n.get_meta("net_id"))
		rpc_id(1, "net_hit", pid, amount)

@rpc("any_peer", "call_remote", "reliable")
func net_asset_hit(zone_label: String, idx: int, amount: float) -> void:
	if not is_host or world == null:
		return
	for z in world.get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z) or String(z.label) != zone_label:
			continue
		if idx < 0 or idx >= z.assets.size():
			return
		var a = z.assets[idx]
		if is_instance_valid(a) and a.has_method("apply_damage"):
			a.apply_damage(amount)
			if verbose:
				print("[net] %s asset %d took %.0f from a client, alive=%s" % [
					zone_label, idx, amount, str(a.get("alive"))])
		return

## Damage that landed on a ghost. A ghost is a picture of somebody else's
## aircraft, so it cannot decide whether it just died: the hit goes to whoever
## is simulating the real one and comes back as replicated state.
func report_damage(g: Node, amount: float) -> void:
	if not active:
		return
	if g.has_meta("net_ai"):
		var key := int(g.get_meta("net_ai"))
		if is_host:
			_apply_ai_hit(key, amount)
		else:
			if verbose:
				print("[net] reporting %.0f damage on ai %d to the host" % [amount, key])
			rpc_id(1, "net_ai_hit", key, amount)
		return
	if g.has_meta("net_id"):
		var pid := int(g.get_meta("net_id"))
		if is_host:
			rpc_id(pid, "net_hit", pid, amount)
		else:
			rpc_id(1, "net_hit", pid, amount)

# --------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not active or world == null:
		return
	# prune anything that went away before touching it: a typed read of a freed
	# object aborts the whole function
	for id in ghosts.keys():
		if not is_instance_valid(ghosts[id]):
			ghosts.erase(id)
	for id in veh_ghosts.keys():
		if not is_instance_valid(veh_ghosts[id]):
			veh_ghosts.erase(id)
	for id in ai_ghosts.keys():
		if not is_instance_valid(ai_ghosts[id]):
			ai_ghosts.erase(id)
	if not is_host:
		for z in world.get_tree().get_nodes_in_group("zones"):
			if not is_instance_valid(z):
				continue
			for a in z.assets:
				if not is_instance_valid(a) or not a.has_meta("gnd_pos"):
					continue
				var gk: float = clampf(delta * 12.0, 0.0, 1.0)
				a.global_position = a.global_position.lerp(
					a.get_meta("gnd_pos") as Vector3, gk)
				a.rotation.y = lerp_angle(a.rotation.y,
					a.get_meta("gnd_rot") as float, gk)
	# Ghosts are kinematic bodies moved on the physics tick: dead reckon along
	# the last reported velocity and ease onto the last reported pose, then let
	# Godot's physics interpolation smooth it out for the renderer.
	for id in veh_ghosts:
		var v: Tank = veh_ghosts[id]
		if not v.has_meta("target_pos"):
			continue
		if _stale(v):
			continue
		var vp: Vector3 = v.get_meta("target_pos") \
			+ (v.get_meta("net_vel", Vector3.ZERO) as Vector3) * delta
		v.set_meta("target_pos", vp)
		var vr: Quaternion = v.get_meta("target_rot")
		var vk: float = clampf(delta * 10.0, 0.0, 1.0)
		var vxf := v.global_transform
		v.global_transform = Transform3D(
			Basis(vxf.basis.get_rotation_quaternion().slerp(vr, vk)),
			vxf.origin.lerp(vp, vk))
	for id in ai_ghosts:
		var a: Aircraft = ai_ghosts[id]
		if not a.has_meta("target_pos"):
			continue
		if _stale(a):
			continue
		var ap: Vector3 = a.get_meta("target_pos") \
			+ (a.get_meta("net_vel", Vector3.ZERO) as Vector3) * delta
		a.set_meta("target_pos", ap)
		var ar: Quaternion = a.get_meta("target_rot")
		var ak: float = clampf(delta * 30.0, 0.0, 1.0)
		var axf := a.global_transform
		a.global_transform = Transform3D(
			Basis(axf.basis.get_rotation_quaternion().slerp(ar, ak)),
			axf.origin.lerp(ap, ak))
	for id in ghosts:
		var g: Aircraft = ghosts[id]
		if not g.has_meta("target_pos"):
			continue
		if _stale(g):
			continue
		var tp: Vector3 = g.get_meta("target_pos")
		tp += (g.get_meta("net_vel", Vector3.ZERO) as Vector3) * delta
		g.set_meta("target_pos", tp)
		var want_rot: Quaternion = g.get_meta("target_rot")
		var k: float = clampf(delta * 10.0, 0.0, 1.0)
		var xf := g.global_transform
		g.global_transform = Transform3D(
			Basis(xf.basis.get_rotation_quaternion().slerp(want_rot, k)),
			xf.origin.lerp(tp, k))
	_acc += delta
	if _acc < RATE:
		return
	_acc = 0.0
	# the host publishes the AI and objective state a few times a second
	if is_host:
		_ai_acc += RATE
		if _ai_acc >= 0.05:
			_ai_acc = 0.0
			_publish_ai()
		_gnd_acc += RATE
		if _gnd_acc >= 0.1:
			_gnd_acc = 0.0
			_publish_ground()
		_ship_acc += RATE
		if _ship_acc >= 0.2:
			_ship_acc = 0.0
			_publish_ships()
		_obj_acc += RATE
		if _obj_acc >= 0.5:
			_obj_acc = 0.0
			var mode = world.get("mode")
			if mode != null and is_instance_valid(mode):
				var labels := PackedStringArray()
				var owners := PackedInt32Array()
				var prog := PackedFloat32Array()
				var masks := PackedInt32Array()
				for z in world.get_tree().get_nodes_in_group("zones"):
					if not is_instance_valid(z):
						continue
					labels.append(String(z.label))
					owners.append(int(z.owner_team))
					prog.append(float(z.progress))
					var m := 0
					for i in mini(z.assets.size(), 31):
						var a = z.assets[i]
						if is_instance_valid(a) and bool(a.get("alive")):
							m |= 1 << i
					masks.append(m)
				rpc("net_objectives", labels, owners, prog, masks,
					int(mode.tickets.get(0, 0)), int(mode.tickets.get(1, 0)))
	# holding the conn of a ship: the orders go over, the hull comes back
	if ship_conn >= 0 and not is_host:
		var sh := _ship_by_index(ship_conn)
		if sh != null and sh.occupied:
			tx += 1
			rpc_id(1, "net_ship_orders", ship_conn, sh.helm, sh.telegraph,
				sh.aim_yaw, sh.aim_pitch)
		return
	# in a vehicle: send the hull and turret instead
	var tk = world.get("tank")
	if tk != null and is_instance_valid(tk):
		rpc("net_vehicle", my_id, tk.global_position,
			tk.global_transform.basis.get_rotation_quaternion(), tk.linear_velocity,
			tk.turret_yaw, tk.turret_pitch)
		return
	# on foot: send the walker instead of the jet
	if world.get("on_foot"):
		var w = world.get("walker")
		if w != null and is_instance_valid(w):
			var host_id := 0
			if w.frame != null and is_instance_valid(w.frame_owner):
				host_id = my_id
				for pid in ghosts:
					if ghosts[pid] == w.frame_owner:
						host_id = pid
			rpc("net_foot", my_id, w.position, w.yaw, w.crouching, host_id)
		return
	var p = world.get("player")
	if p == null or not is_instance_valid(p):
		return
	var flags := 0
	if p.gear_down:
		flags |= 1
	if p.hook_down:
		flags |= 2
	if p.flaps > 0.5:
		flags |= 4
	if p.any_bay_open():
		flags |= 8
	if not p.is_alive():
		flags |= 16
	tx += 1
	rpc("net_state", my_id, p.global_position,
		p.global_transform.basis.get_rotation_quaternion(), p.linear_velocity,
		p.throttle, flags)

## True once a ghost has gone a second without an update. Extrapolating past
## that walks it off the map: a dropped peer left one 1.8e9 m from the field.
func _stale(n: Node3D) -> bool:
	return Time.get_ticks_msec() - int(n.get_meta("t_rx", 0)) > 1000

## Host side: announce any AI the clients have not been told about, then push
## the whole set's state in one packet.
func _publish_ai() -> void:
	var now := {}
	for n in world.get_tree().get_nodes_in_group("bandits"):
		if is_instance_valid(n) and not n.is_in_group("remote") and n.is_alive():
			now[n.get_instance_id() % 100000] = n
	# anything that has left the live set is dead or despawned; say so once,
	# reliably, or the clients keep a frozen ghost of it for ever
	var gone := PackedInt32Array()
	for key in _ai_seen.keys():
		if not now.has(key):
			gone.append(key)
			_ai_seen.erase(key)
	if gone.size() > 0:
		if verbose:
			print("[net] ai gone: %s" % str(gone))
		rpc("net_ai_gone", gone)
	var new_idx := PackedInt32Array()
	var new_kinds := PackedStringArray()
	var new_teams := PackedInt32Array()
	var idx := PackedInt32Array()
	var pos := PackedVector3Array()
	var rot := PackedFloat32Array()
	var vel := PackedVector3Array()
	var alive := PackedByteArray()
	for key in now:
		var n: Node3D = now[key]
		if not _ai_seen.has(key):
			_ai_seen[key] = true
			new_idx.append(key)
			new_kinds.append(_kind_of(n))
			new_teams.append(int(n.team))
		idx.append(key)
		pos.append(n.global_position)
		var b: Basis = n.global_transform.basis
		rot.append(atan2(-b.z.x, b.z.z))
		rot.append(asin(clampf(-b.z.y, -1.0, 1.0)))
		vel.append(n.linear_velocity)
		alive.append(1)
	if new_idx.size() > 0:
		rpc("net_ai_roster", new_idx, new_kinds, new_teams)
	if idx.size() > 0:
		rpc("net_ai_state", idx, pos, rot, vel, alive)

func _kind_of(n: Node) -> String:
	for id in JetSpec.ids():
		if String(JetSpec.get_spec(id)["name"]) == String(n.spec["name"]):
			return id
	return "f16"

## A deterministic slot for this peer, so two people who pick the same aeroplane
## are not put in the same piece of sky. Derived from the peer id rather than
## from roster order: everyone works it out identically without having to agree
## on who joined first.
func spawn_slot() -> int:
	if not active:
		return 0
	var h: int = absi(my_id)
	return (h % 7) if my_id != 1 else 0

func spawn_offset() -> Vector3:
	var k := spawn_slot()
	if k == 0:
		return Vector3.ZERO
	# a line abreast to starboard, stepped down so nobody is directly above
	return Vector3(float(k) * 70.0, float(k) * -22.0, float(k) * 55.0)

## Called by the local player when it looses a store.
func report_fire(weapon: String, xf: Transform3D, vel: Vector3) -> void:
	if active:
		rpc("net_fire", my_id, weapon, xf.origin, xf.basis.get_rotation_quaternion(), vel)
