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

## Callsigns, generated when you connect.
##
## Everyone was "P" and their peer number, which is a routing detail rather than
## a name -- and on the host's own screen the host was "Host". With a roster
## screen and labels over people's aeroplanes that had to be something you could
## actually say over the radio.
const CALL_A := ["VIPER", "REAPER", "BANDIT", "COBRA", "HAVOC", "SABRE",
	"TALON", "RAZOR", "GHOST", "FALCON", "OUTLAW", "JACKAL", "MAVERICK",
	"DAGGER", "HAMMER", "WIDOW", "RONIN", "TEMPEST", "GRIFFIN", "ROGUE"]

static func callsign() -> String:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return "%s %d" % [CALL_A[r.randi() % CALL_A.size()], r.randi_range(1, 9)]

## My own callsign, picked once and kept for the session.
var my_name := ""

func name_of(id: int) -> String:
	if roster.has(id):
		return String((roster[id] as Dictionary).get("name", "P%d" % id))
	return "P%d" % id
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
var _wx_acc := 0.0
var verbose := false
var upnp_ready := false           # the router forwarded the port
var upnp_external := ""           # the address other people should use
var _upnp: UPNP = null
var _upnp_thread: Thread = null
var tx := 0
var rx := 0
var status := "offline"

## The parts of the session kept in their own scripts; see each class. They
## are children, so their RPCs have the same path on every peer.
var ships := NetShips.new(self)
var units := NetUnits.new(self)
var launches := NetLaunches.new(self)

func _init() -> void:
	add_child(ships)
	add_child(units)
	add_child(launches)

# --------------------------------------------------------------------------
## Where the game is listening. Always PORT; kept as a variable only so the
## UPnP mapping and the join address read from one place.
var port := PORT
## A different port for the test harness (--netport=N), so a test session on
## this machine never meets a game the player has open on the real one.
static var port_override := 0

func host(jet_id: String) -> bool:
	_shut = false
	# Anything still holding the socket has to go first. Hosting twice without
	# leaving in between, or a previous attempt that failed after creating the
	# peer, leaves the old one bound and the next `create_server` fails with an
	# engine error and no explanation.
	_drop_peer()
	var peer := ENetMultiplayerPeer.new()
	# One port, the published one, so the address you read out is always the
	# same and a joiner never has to be told a different number. If it is busy
	# the answer is to find out why, not to move quietly to 27016 and leave
	# everyone guessing — and the reason is almost always this game itself,
	# still running from a session that was not shut down.
	port = PORT if port_override <= 0 else port_override
	var err := peer.create_server(port, 8)
	if err != OK:
		status = "host failed (%d)" % err
		Sim.report("Port %d is already in use — another copy of the game is "
			% port + "probably still running. Close it and host again.", Sim.Ev.BAD)
		return false
	multiplayer.multiplayer_peer = peer
	# `connect` on an already-connected signal raises, and leaving a session
	# never disconnected these, so the second host of a sitting was fatal.
	if not multiplayer.peer_connected.is_connected(_on_peer_joined):
		multiplayer.peer_connected.connect(_on_peer_joined)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
		multiplayer.peer_disconnected.connect(_on_peer_left)
	active = true
	is_host = true
	my_id = 1
	if my_name == "":
		my_name = callsign()
	roster[1] = {"jet": jet_id, "name": my_name, "team": abs_side}
	status = "hosting on port %d" % port
	Sim.report("Hosting. Others join at %s" % join_address(), Sim.Ev.GOOD)
	_open_port()
	roster_changed.emit()
	return true

## Everyone in the session and where they are: id, name, team, and a position if
## there is anything of theirs in the world to point at. What the roster screen
## and the map both read.
func player_positions() -> Array:
	var out: Array = []
	for pid in roster:
		var e: Dictionary = roster[pid]
		var at := Vector3.INF
		var kind := "air"
		if int(pid) == my_id:
			# whatever this player is actually sitting in
			for mine in [world.get("player") if world != null else null,
					world.get("tank") if world != null else null,
					world.get("walker") if world != null else null,
					world.get("ship") if world != null else null]:
				if mine != null and is_instance_valid(mine):
					at = (mine as Node3D).global_position
					break
		elif ghosts.has(pid) and is_instance_valid(ghosts[pid]):
			at = (ghosts[pid] as Node3D).global_position
		elif veh_ghosts.has(pid) and is_instance_valid(veh_ghosts[pid]):
			at = (veh_ghosts[pid] as Node3D).global_position
			kind = "ground"
		elif foot_ghosts.has(pid) and is_instance_valid(foot_ghosts[pid]):
			at = (foot_ghosts[pid] as Node3D).global_position
			kind = "foot"
		out.append({"id": int(pid), "name": String(e.get("name", "P%d" % pid)),
			"team": int(e.get("team", 0)), "jet": String(e.get("jet", "")),
			"at": at, "kind": kind, "me": int(pid) == my_id})
	return out

## The address to read out to whoever is joining, with the port always on it.
##
## The port is not decoration: if the usual one was busy the game is listening
## somewhere else, and a joiner typing the bare IP will not find it. It is also
## no use in a mission-log line that scrolls away thirty seconds later, which is
## where it used to be and only there.
func join_address() -> String:
	if not is_host:
		return ""
	if upnp_ready and upnp_external != "":
		return "%s:%d" % [upnp_external, port]
	var lan := local_ip()
	return "%s:%d" % [lan, port] if lan != "" else "port %d" % port

## This machine's address on its own network. Loopback and IPv6 are no use to
## somebody typing an address on another computer.
func local_ip() -> String:
	for a in IP.get_local_addresses():
		var ip := String(a)
		if ip.begins_with("127.") or ip.contains(":"):
			continue
		if ip.begins_with("169.254."):
			continue
		return ip
	return ""

## What the hangar shows while a session is up.
## Bytes a second on the wire, sent and received.
##
## The log counted *packets*, and a packet is anything from twenty bytes to a
## kilobyte -- so "tx=412" says nothing about whether a session survives a real
## connection, which for a multiplayer game is the question. ENet keeps the byte
## totals on the host connection, and popping them is what resets them, so this
## is genuinely the traffic since it was last asked.
var _wire_t := 0.0

func wire_rate() -> Vector2:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or not active:
		return Vector2.ZERO
	var conn := peer.get_host()
	if conn == null:
		return Vector2.ZERO
	var sent := float(conn.pop_statistic(
		ENetConnection.HOST_TOTAL_SENT_DATA))
	var got := float(conn.pop_statistic(
		ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	var now := float(Time.get_ticks_msec()) * 0.001
	var span := now - _wire_t
	_wire_t = now
	if span < 0.05 or span > 30.0:
		return Vector2.ZERO
	return Vector2(sent, got) / span

## What the link is doing, in milliseconds, as ENet last measured it.
func round_trip_ms() -> float:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or not active:
		return 0.0
	var worst := 0.0
	for id in roster:
		var pid := int(id)
		if pid == my_id:
			continue
		var pp := peer.get_peer(pid)
		if pp != null:
			worst = maxf(worst, pp.get_statistic(
				ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME))
	return worst

func status_line() -> String:
	if not active:
		return status
	if is_host:
		var where := join_address()
		var via := "port forwarded" if upnp_ready else "local network only"
		return "HOSTING — others join at  %s   (%s, %d connected)" % [
			where, via, maxi(roster.size() - 1, 0)]
	return "%s — %d in the session" % [status, roster.size()]

## Shutting the window is the common way out of this game, and until now it took
## the socket and the router mapping with it — the port stayed bound for as long
## as the process lingered, and the next session could not host. Godot only
## sends the close notification when the quit is not automatic, so the tree
## teardown is covered too.
func _ready() -> void:
	get_tree().set_auto_accept_quit(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()
		get_tree().quit()
	elif what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		shutdown()

## Hand back the port and the router mapping. Safe to call more than once.
func shutdown() -> void:
	if _shut:
		return
	_shut = true
	_close_port()
	_drop_peer()
	active = false

var _shut := false

## Let go of the socket, whatever state it is in.
func _drop_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

## Ask the router to forward the port so somebody outside the house can actually
## reach the game. Discovery talks to the network and takes seconds, so it runs
## on its own thread: doing it inline froze the frame the match started on.
func _open_port() -> void:
	if _upnp_thread != null:
		return
	# Made here, on the main thread, and handed over. Godot finishes setting
	# up a class the first time one is made, and doing that from the worker
	# -- the UPNP itself, and the devices `discover` makes -- printed
	# "Finalizing a GDType from a subtype from another thread" on every host.
	var up := UPNP.new()
	var _warm := UPNPDevice.new()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(up))

func _upnp_worker(up: UPNP) -> void:
	var disc := up.discover()
	if disc != UPNP.UPNP_RESULT_SUCCESS:
		_upnp_done.call_deferred(false, "", "no router answered (%d)" % disc)
		return
	var gw := up.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		_upnp_done.call_deferred(false, "", "router does not do UPnP")
		return
	# ENet is UDP; map TCP too so a future lobby or query port works
	var r1 := up.add_port_mapping(port, port, "flight sim", "UDP", 0)
	up.add_port_mapping(port, port, "flight sim", "TCP", 0)
	if r1 != UPNP.UPNP_RESULT_SUCCESS:
		_upnp_done.call_deferred(false, "", "router refused the mapping (%d)" % r1)
		return
	_upnp = up
	_upnp_done.call_deferred(true, up.query_external_address(), "")

func _upnp_done(ok: bool, ip: String, why: String) -> void:
	upnp_ready = ok
	upnp_external = ip
	if ok:
		status = "hosting on %s:%d" % [ip, port]
		Sim.report("Port forwarded — others can join at %s:%d" % [ip, port], Sim.Ev.GOOD)
	else:
		Sim.report("No port forwarding: %s. Players on your own network can " % why
			+ "still join by local IP.", Sim.Ev.INFO)
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	_upnp_thread = null

## Hand the port back when the match ends, so it is not left open.
func _close_port() -> void:
	if _upnp != null:
		_upnp.delete_port_mapping(port, "UDP")
		_upnp.delete_port_mapping(port, "TCP")
		_upnp = null
	upnp_ready = false
	upnp_external = ""

## `address` may carry a port — "10.0.0.4:27016" — because a host whose usual
## port was busy will be listening on another one and has to be reachable there.
func join(address: String, jet_id: String) -> bool:
	_shut = false
	_drop_peer()
	var host_ip := address.strip_edges()
	var want := PORT if port_override <= 0 else port_override
	var colon := host_ip.rfind(":")
	if colon > 0 and host_ip.substr(colon + 1).is_valid_int():
		want = int(host_ip.substr(colon + 1))
		host_ip = host_ip.substr(0, colon)
	if host_ip == "":
		host_ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host_ip, want)
	if err != OK:
		status = "join failed (%d)" % err
		Sim.report("Could not reach %s on port %d." % [host_ip, want], Sim.Ev.BAD)
		return false
	port = want
	multiplayer.multiplayer_peer = peer
	# same reason as the host side: these are never disconnected on leave, so
	# joining twice in one sitting connected them twice
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected.bind(jet_id))
	if not multiplayer.connection_failed.is_connected(_on_failed):
		multiplayer.connection_failed.connect(_on_failed)
	if not multiplayer.server_disconnected.is_connected(_on_dropped):
		multiplayer.server_disconnected.connect(_on_dropped)
	active = true
	is_host = false
	status = "connecting to %s:%d" % [host_ip, want]
	Sim.report("Connecting to %s on port %d..." % [host_ip, want], Sim.Ev.INFO)
	return true

func leave() -> void:
	_close_port()
	_drop_peer()
	if multiplayer.peer_connected.is_connected(_on_peer_joined):
		multiplayer.peer_connected.disconnect(_on_peer_joined)
	if multiplayer.peer_disconnected.is_connected(_on_peer_left):
		multiplayer.peer_disconnected.disconnect(_on_peer_left)
	for d in [ghosts, foot_ghosts, veh_ghosts, ai_ghosts]:
		_free_all(d)
	units.clear(not is_host)
	_gen_loaded = -1
	match_gen = 0
	ships.reset()
	ai_kinds.clear()
	_ai_seen.clear()
	roster.clear()
	active = false
	is_host = false
	if side == 1:
		side = 0
		ships.side_fleet()
	status = "offline"
	roster_changed.emit()

# --------------------------------------------------------------------------
func _on_peer_joined(id: int) -> void:
	Sim.report("player %d joined" % id, Sim.Ev.GOOD)
	# tell the newcomer what we are playing, then hand over the roster
	# Two different things, and sending only the first was a regression: the
	# lobby message tells a joiner what the host has *selected*, so its hangar
	# shows the right match and cannot pick another. `net_match` is what makes
	# it actually load the match that is already running. Without it every
	# joiner stayed in whatever it had launched locally — three clients sitting
	# on identical default start points, in a mission the host was not flying.
	rpc_id(id, "net_lobby_mission", lobby_mission if lobby_mission != ""
		else String(Sim.mission))
	# Only a match that is actually running: a host still in the hangar has
	# nothing to load, and the joiner waits there with it.
	if world.get("running") and running_mission != "":
		if match_gen == 0:
			match_gen = 1
		rpc_id(id, "net_match", running_mission, match_gen, match_settings())
	_publish_weather.call_deferred()      # and the sky they are joining
	for pid in roster:
		rpc_id(id, "net_announce", pid, roster[pid]["jet"], roster[pid]["team"],
			String(roster[pid].get("name", "P%d" % pid)))
	# the AI roster was announced to whoever was connected at the time, so
	# forget it and let the next publish describe the whole set again
	_ai_seen.clear()

func _on_peer_left(id: int) -> void:
	Sim.report("player %d left" % id, Sim.Ev.BAD)
	if ghosts.has(id) and is_instance_valid(ghosts[id]):
		(ghosts[id] as Aircraft).spill_hold()
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
	if my_name == "":
		my_name = callsign()
	rpc("net_announce", my_id, jet_id, abs_side, my_name)
	net_announce(my_id, jet_id, abs_side, my_name)
	ships.side_fleet()
	ships.set_ghosts(true)

func _on_failed() -> void:
	status = "connection failed"
	Sim.report("Connection failed", Sim.Ev.BAD)
	active = false

func _on_dropped() -> void:
	status = "host closed"
	Sim.report("Host closed the session", Sim.Ev.BAD)
	leave()

# --------------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func net_lobby_mission(m: String) -> void:
	if is_host or world == null:
		return
	lobby_mission = m
	roster_changed.emit()

## What the host has selected but not yet launched. Clients show this and are
## not allowed to choose anything else.
var lobby_mission := ""

func announce_lobby(m: String) -> void:
	if active and is_host:
		lobby_mission = m
		rpc("net_lobby_mission", m)

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
	mode.tickets[lt(0)] = t_us
	mode.tickets[lt(1)] = t_them
	for z in world.get_tree().get_nodes_in_group("zones"):
		if not is_instance_valid(z):
			continue
		var idx := labels.find(String(z.label))
		if idx < 0:
			continue
		z.owner_team = lt(owners[idx])
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
func net_announce(id: int, jet_id: String, team: int, nm := "") -> void:
	roster[id] = {"jet": jet_id, "team": team,
		"name": nm if nm != "" else "P%d" % id}
	if verbose:
		print("[net] announce id=%d jet=%s from=%d roster=%d" % [
			id, jet_id, multiplayer.get_remote_sender_id(), roster.size()])
	# a different aircraft than the ghost is drawn as: built again as this one
	if id != my_id and ghosts.has(id) and is_instance_valid(ghosts[id]) \
			and String((ghosts[id] as Node).get_meta("jet", jet_id)) != jet_id:
		var old: Aircraft = ghosts[id]
		var keep_xf := old.global_transform
		ghosts.erase(id)
		old.spill_hold()
		old.queue_free()
		# hidden until his next packet puts it somewhere: back on foot after a
		# gunship there may be no more of them, and it hung in the sky
		_make_ghost(id, jet_id, peer_team(id))
		if ghosts.has(id):
			(ghosts[id] as Aircraft).global_transform = keep_xf
	if id != my_id and not ghosts.has(id):
		_make_ghost(id, jet_id, peer_team(id))
	elif id != my_id and is_instance_valid(ghosts[id]):
		(ghosts[id] as Aircraft).team = peer_team(id)
	if id != my_id and veh_ghosts.has(id) and is_instance_valid(veh_ghosts[id]):
		(veh_ghosts[id] as Tank).team = peer_team(id)
	if is_host and id != 1:
		# relay to everyone else
		rpc("net_announce", id, jet_id, team, String(roster[id]["name"]))
	if id == 1 or id == my_id:
		_recompute_side()
	else:
		_retag_players()
	roster_changed.emit()

## This player's aircraft is now a different one -- a gunship he has been put
## on, and back again after -- and every other screen redraws his ghost.
func set_jet(jet_id: String) -> void:
	if not active or not roster.has(my_id):
		return
	roster[my_id]["jet"] = jet_id
	var nm := String(roster[my_id].get("name", ""))
	rpc("net_announce", my_id, jet_id, abs_side, nm)

func _make_ghost(id: int, jet_id: String, team: int) -> void:
	if world == null:
		return
	var g := Aircraft.new()
	g.setup(jet_id)
	g.set_meta("jet", jet_id)
	# Another player's transport can be walked into when its ramp is down --
	# it is offered to a man on foot for that and nothing else (see
	# `Walker._scan` and `Crew.board`).
	if g.has_hold():
		g.add_to_group("boardable")
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
	var g: Aircraft = live(ghosts, id) as Aircraft
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
			g.wrecked = true
			g.wreck_visuals()
	# both dispensers, so a remote aeroplane defending itself looks like one
	if (flags & 32) != 0:
		g.drop_flare()
	if (flags & 64) != 0:
		g.drop_chaff()
	g.gear_down = bool(flags & 1)
	g.hook_down = bool(flags & 2)
	g.ramp_open = (flags & 128) != 0
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
func net_foot(id: int, pos: Vector3, yaw: float, crouch: bool, in_hold_of: int,
		kit := "", pitch := 0.0, ads := 0.0, dead := false) -> void:
	# The host passes every man's position on to everyone -- him included.
	# Taken as somebody else, it built a second copy of him a tick behind
	# himself: two of him in the hold, on his own screen.
	if id == my_id:
		return
	# a Variant first: a freed object handed to a typed variable is an error
	var gv: Variant = foot_ghosts.get(id)
	var g: Node3D = gv as Node3D if is_instance_valid(gv) else null
	if g == null:
		var pil := Pilot.new()
		pil.build()
		pil.name = "Crew %d" % id
		# what everyone else's rounds, grenades and riflemen find: see NetMan
		var man := NetMan.new()
		man.name = "Man"
		man.peer = id
		man.team = peer_team(id)
		man.callsign = name_of(id)
		pil.add_child(man)
		world.add_child(pil)
		foot_ghosts[id] = pil
		g = pil
	var want_parent: Node = world
	if in_hold_of != 0:
		var carrier_jet: Aircraft = live(ghosts, in_hold_of) as Aircraft
		if in_hold_of == my_id and world.get("player") != null:
			carrier_jet = world.get("player")
		if carrier_jet and is_instance_valid(carrier_jet) and carrier_jet.has_hold():
			want_parent = carrier_jet.hold_node()
	if g.get_parent() != want_parent:
		g.get_parent().remove_child(g)
		want_parent.add_child(g)
	# Square to whatever he is standing in, every packet. Moved into the hold
	# keeping his world orientation, he kept the bank the aircraft had at that
	# moment, and only his heading was ever set again: he stood at an angle to
	# the floor for the rest of the flight.
	# Where he is goes in as a target, eased toward every frame (see
	# `_tick_foot_ghosts`), and what he is doing -- the weapon in his hands,
	# where he is looking, how far into the sights -- drives the same figure
	# he is on his own screen. It was a mannequin stood in one pose: no
	# weapon, never aiming, never firing.
	if not g.has_meta("net_pos") or g.position.distance_to(pos) > 4.0:
		g.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	g.set_meta("net_pos", pos)
	g.set_meta("net_yaw", yaw)
	g.set_meta("net_crouch", crouch)
	g.set_meta("net_pitch", pitch)
	g.set_meta("net_ads", ads)
	g.set_meta("t_rx", Time.get_ticks_msec())
	var nm: NetMan = g.get_node_or_null("Man") as NetMan
	if nm != null:
		nm.team = peer_team(id)
		nm.crouching = crouch
		nm.yaw = yaw
		nm.dead = dead
	# a dead man lies where he fell as a ragdoll on his own screen; the
	# standing figure goes until he is back on his feet
	g.visible = not dead
	if g is Pilot and kit != "" and String(g.get_meta("net_kit", "")) != kit:
		g.set_meta("net_kit", kit)
		(g as Pilot).equip(Firearm.spec(kit))
	if is_host:
		rpc("net_foot", id, pos, yaw, crouch, in_hold_of, kit, pitch, ads, dead)

## Every remote man on foot, every frame: eased to where he was last said to
## be, and animated -- walking, crouched, the weapon up and laid where he is
## looking -- by the same rig his own machine draws him with.
func _tick_foot_ghosts(delta: float) -> void:
	for id in foot_ghosts:
		var g: Variant = foot_ghosts[id]
		if not is_instance_valid(g) or not (g is Pilot) or not (g as Node3D).has_meta("net_pos"):
			continue
		var pil := g as Pilot
		# A man whose packets have stopped has got into something or gone:
		# not left standing as a target where he last was.
		var quiet_ms: int = Time.get_ticks_msec() - int(pil.get_meta("t_rx", Time.get_ticks_msec()))
		var nm: NetMan = pil.get_node_or_null("Man") as NetMan
		if quiet_ms > 1500:
			pil.visible = false
			if nm != null:
				nm.dead = true
			continue
		var want: Vector3 = pil.get_meta("net_pos")
		var was: Vector3 = pil.position
		pil.position = was.lerp(want, clampf(delta * 14.0, 0.0, 1.0))
		pil.rotation = Vector3(0.0, lerp_angle(pil.rotation.y, float(pil.get_meta("net_yaw")),
			clampf(delta * 14.0, 0.0, 1.0)), 0.0)
		# how he is moving, in his own frame: x to his right, y forward
		var v: Vector3 = (pil.position - was) / maxf(delta, 0.0001)
		var yw: float = pil.rotation.y
		var right := Vector3(cos(yw), 0, -sin(yw))
		var fwd := Vector3(-sin(yw), 0, -cos(yw))
		pil.in_move = pil.in_move.lerp(Vector2(v.dot(right), v.dot(fwd)), clampf(delta * 8.0, 0.0, 1.0))
		pil.in_crouch = bool(pil.get_meta("net_crouch"))
		pil.in_pitch = float(pil.get_meta("net_pitch"))
		pil.in_ads = float(pil.get_meta("net_ads"))
		pil.in_ready = 1.0
		# feet onto the ground only on the ground: in a hold the ground is a
		# kilometre down, and the legs went looking for it
		pil.in_foot_ik = pil.get_parent() == world
		pil.animate(delta)

## A man on foot here fired: tell everyone else, so they see and hear it.
## `carrier_vel` is the speed of whatever he is riding in.
func send_foot_shot(from: Vector3, dir: Vector3, kit: String, quiet: bool,
		carrier_vel := Vector3.ZERO) -> void:
	if not active:
		return
	if is_host:
		rpc("net_foot_shot", my_id, from, dir, kit, quiet, carrier_vel)
	else:
		rpc_id(1, "net_foot_shot", my_id, from, dir, kit, quiet, carrier_vel)

## The shot as seen from somewhere else: the flash at his muzzle, the report,
## and a round down the line that hurts nothing -- the hit, if there is one,
## comes over on its own (`net_hit`), from the machine that fired.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_foot_shot(id: int, from: Vector3, dir: Vector3, kit: String, quiet: bool,
		carrier_vel := Vector3.ZERO) -> void:
	if id == my_id:
		return
	if is_host:
		rpc("net_foot_shot", id, from, dir, kit, quiet, carrier_vel)
	var g: Dictionary = Firearm.spec(kit)
	var muzzle: Vector3 = from
	var gh: Variant = foot_ghosts.get(id)
	if is_instance_valid(gh) and (gh as Pilot).has_gun():
		muzzle = (gh as Pilot).muzzle_pos()
		(gh as Pilot).kick(float(g.get("kick", 0.01)) * 30.0)
	Effects.muzzle_flash(world, muzzle + dir * 0.12, dir, 0.045 if quiet else 0.16)
	if not quiet:
		Firearm.report(world, g, muzzle)
	# harmless, and stopped by the same hulls the real one is
	# On his side: a copy with no side struck everyone, his friends and the
	# man at this keyboard included -- no damage, but the hit and the blood.
	var t_side: int = peer_team(id)
	Effects.bullet(world, muzzle, dir * float(g["muzzle"]) + carrier_vel,
		null, 0.0, t_side, 1.0, 3.5, Firearm.drag_of(g), 0.0)

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
		g.team = lt(teams[i])
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
		var g: Aircraft = live(ai_ghosts, idx[i]) as Aircraft
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
		var g: Aircraft = live(ai_ghosts, key) as Aircraft
		ai_ghosts.erase(key)
		ai_kinds.erase(key)
		if g != null and is_instance_valid(g):
			if verbose:
				print("[net] ai %d removed by the host" % key)
			if g.visible:
				Effects.explosion(world, g.global_position, 12.0)
			g.queue_free()

# --------------------------------------------------------------- weather
## The sky is host-authoritative, like everything else that everyone has to
## agree on. Two players flying the same sortie at different times of day, one
## in daylight and one at dusk, is not a cosmetic difference: it changes what
## you can see and what can see you.
@rpc("authority", "call_remote", "reliable")
func net_weather(id: String, hour: float, rate: float) -> void:
	if is_host or world == null:
		return
	var w = world.get("weather")
	if w == null or not is_instance_valid(w):
		return
	if String(w.current) != id:
		world.call("set_weather", id)
	w.time_of_day = hour
	w.time_rate = rate

func _publish_weather() -> void:
	var w = world.get("weather")
	if w == null or not is_instance_valid(w):
		return
	rpc("net_weather", String(w.current), float(w.time_of_day), float(w.time_rate))

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
		box.post(who, text.substr(0, 140), lt(team ^ host_abs()))

func say(text: String) -> void:
	if not active:
		return
	var who := "P%d" % my_id
	var team := 0
	if roster.has(my_id):
		who = String(roster[my_id].get("name", who))
		team = int(roster[my_id].get("team", 0))
	rpc("net_chat", who, text.substr(0, 140), team)
	# (absolute: see `side`)


## Ground vehicles replicate the same way as aircraft: a kinematic stand-in
## eased onto the last reported pose on the physics tick.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_vehicle(id: int, pos: Vector3, rot: Quaternion, vel: Vector3, turret: float,
		barrel: float, flags: int = 1) -> void:
	if id == my_id:
		return                 # our own, passed back to us by the host
	var t: Tank = live(veh_ghosts, id) as Tank
	if t == null or not is_instance_valid(t):
		t = Tank.new()
		t.setup(peer_team(id))
		t.name = "Armour %d" % id
		t.make_picture()
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
	# A vehicle somebody else is driving used to have no way of saying it had
	# died: the packet carried a pose and nothing else, so a tank destroyed on
	# one screen simply stopped moving on every other one, intact and upright.
	if (flags & 1) == 0 and bool(t.alive):
		t.apply_damage(1.0e6)          # turret off, burning, the same as at home
	if is_host:
		rpc("net_vehicle", id, pos, rot, vel, turret, barrel, flags)

@rpc("any_peer", "call_remote", "reliable")
func net_fire(id: int, weapon: String, origin: Vector3, basis_q: Quaternion, vel: Vector3) -> void:
	if world == null:
		return
	var m := Missile.new()
	var xf := Transform3D(Basis(basis_q), origin)
	var shooter: Node = live(ghosts, id)
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
	var n := ai_by_key(key)
	if n == null:
		return
	n.take_hit(amount)
	if verbose:
		print("[net] ai %d took %.0f from a client, hp=%s alive=%s" % [
			key, amount, str(n.get("health")), str(n.is_alive())])

## The number an AI aircraft goes by on the wire.
static func ai_key(n: Node) -> int:
	return n.get_instance_id() % 100000

## Host: the AI aircraft that number names, or null.
func ai_by_key(key: int) -> Node3D:
	for n in world.get_tree().get_nodes_in_group("bandits"):
		if is_instance_valid(n) and not n.is_in_group("remote") and ai_key(n) == key:
			return n
	return null

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
			launches.watch(a)
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
	var a := zone_asset(zone_label, idx)
	if a != null and a.has_method("apply_damage"):
		a.apply_damage(amount)
		if verbose:
			print("[net] %s asset %d took %.0f from a client, alive=%s" % [
				zone_label, idx, amount, str(a.get("alive"))])

## A sector's asset by the sector's label and its slot: both ends built the
## same garrison in the same order.
func zone_asset(label: String, idx: int) -> Node3D:
	for z in world.get_tree().get_nodes_in_group("zones"):
		if is_instance_valid(z) and String(z.label) == label and idx >= 0 and idx < z.assets.size():
			var a: Variant = z.assets[idx]
			return a as Node3D if is_instance_valid(a) else null
	return null

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
	# Wrapped so the whole of it can be timed at once, and so the tags below
	# survive the several early returns in it.
	var _pn := Sim.prof_at()
	_tick_net(delta)
	_tick_foot_ghosts(delta)
	units.tick(delta)
	Sim.prof_end(&"net.total", _pn)

func _tick_net(delta: float) -> void:
	var _pp := Sim.prof_at()
	# prune anything that went away before touching it: a typed read of a freed
	# object aborts the whole function
	_prune(ghosts)
	_prune(veh_ghosts)
	_prune(ai_ghosts)
	Sim.prof_end(&"net.prune", _pp)
	var _pz := Sim.prof_at()
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
	Sim.prof_end(&"net.zones", _pz)
	var _pg := Sim.prof_at()
	# Ghosts are kinematic bodies moved on the physics tick: dead reckon along
	# the last reported velocity and ease onto the last reported pose, then let
	# Godot's physics interpolation smooth it out for the renderer.
	for id in veh_ghosts:
		_ease_ghost(veh_ghosts[id], delta, 10.0)
	for id in ai_ghosts:
		_ease_ghost(ai_ghosts[id], delta, 30.0)
	for id in ghosts:
		_ease_ghost(ghosts[id], delta, 10.0)
	Sim.prof_end(&"net.ghosts", _pg)
	_acc += delta
	if _acc < RATE:
		return
	_acc = 0.0
	var _ps := Sim.prof_at()
	_send(delta)
	Sim.prof_end(&"net.send", _ps)

## What a dictionary holds under `k`, or null if it is not there or has been
## freed. A freed object handed to a typed variable is an error, and anything
## held here can be freed under us: a passenger with his aircraft, a ghost
## rebuilt as another type.
static func live(d: Dictionary, k: Variant) -> Node:
	var v: Variant = d.get(k)
	return v as Node if is_instance_valid(v) else null

## Drop anything that went away.
##
## A dictionary may not be erased from while it is being walked, so the removal
## has to go through `keys()` -- and that builds a fresh array every call, at
## the physics rate, for a list that changes when somebody leaves. The walk that
## finds out whether there *is* anything to drop allocates nothing, and almost
## always there is not.
static func _prune(d: Dictionary) -> void:
	var any := false
	for id in d:
		if not is_instance_valid(d[id]):
			any = true
			break
	if not any:
		return
	for id in d.keys():
		if not is_instance_valid(d[id]):
			d.erase(id)

## Free everything a dictionary holds, and empty it.
static func _free_all(d: Dictionary) -> void:
	for k in d:
		if is_instance_valid(d[k]):
			(d[k] as Node).queue_free()
	d.clear()

## What goes out on the wire, at `RATE`.
##
## Nothing at all when nobody is listening. ENet already drops it -- measured, a
## host with an empty lobby puts 0.0 kB/s on the wire -- but the state is still
## gathered and serialised first: eight aircraft into packed arrays, twenty
## times a second, for nobody. A lobby waiting for players is exactly when the
## frame wants to be smooth.
func _send(_delta: float) -> void:
	# The host only. A client always has somebody to talk to -- the host -- and
	# a freshly joined one whose roster has not arrived yet must still send its
	# own state or the handshake never completes.
	if is_host and roster.size() <= 1:
		return
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
			units.publish()
		ships.publish(RATE)
		_wx_acc += RATE
		if _wx_acc >= 2.0:      # the clock drifts slowly; so can the packet
			_wx_acc = 0.0
			_publish_weather()
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
				rpc("net_kills", int(mode.kills.get(0, 0)), int(mode.kills.get(1, 0)))
	# A gunship called in and on its way, before he is on its guns: it is his
	# aircraft as far as everybody else is concerned (see `set_jet`).
	var gs = world.get("called_gunship")
	if gs != null and is_instance_valid(gs) and gs != world.get("player"):
		tx += 1
		rpc("net_state", my_id, gs.global_position,
			gs.global_transform.basis.get_rotation_quaternion(), gs.linear_velocity,
			gs.throttle, 0)
	# holding the conn of a ship: the orders go over, the hull comes back
	if ships.send_orders():
		return
	# in a vehicle: send the hull and turret instead
	var tk = world.get("tank")
	if tk != null and is_instance_valid(tk):
		launches.watch(tk)
		rpc("net_vehicle", my_id, tk.global_position,
			tk.global_transform.basis.get_rotation_quaternion(), tk.linear_velocity,
			tk.turret_yaw, tk.turret_pitch, 1 if tk.alive else 0)
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
			rpc("net_foot", my_id, w.position, w.yaw, w.crouching, host_id,
				String(w.gun_spec().get("id", "")), w.pitch, w._ads, bool(w.dead))
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
	if p.flare_active():
		flags |= 32
	if p.chaff_active():
		flags |= 64
	# The cargo ramp. It was not in the packet, so another player's C-130 was
	# shut on every screen but his, and nobody could walk into its hold.
	if bool(p.get("ramp_open")):
		flags |= 128
	tx += 1
	rpc("net_state", my_id, p.global_position,
		p.global_transform.basis.get_rotation_quaternion(), p.linear_velocity,
		p.throttle, flags)

## A ghost moved one physics tick: dead reckoned along its last reported
## velocity and eased onto its last reported pose, `rate` being how hard.
func _ease_ghost(g: Node3D, delta: float, rate: float) -> void:
	if not g.has_meta("target_pos") or _stale(g):
		return
	var tp: Vector3 = g.get_meta("target_pos")
	tp += (g.get_meta("net_vel", Vector3.ZERO) as Vector3) * delta
	g.set_meta("target_pos", tp)
	var want_rot: Quaternion = g.get_meta("target_rot")
	var k: float = clampf(delta * rate, 0.0, 1.0)
	var xf := g.global_transform
	g.global_transform = Transform3D(
		Basis(xf.basis.get_rotation_quaternion().slerp(want_rot, k)),
		xf.origin.lerp(tp, k))

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
			now[ai_key(n)] = n
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
		launches.watch(n)
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
## A slot per peer, and no two the same.
##
## Hashing the peer id was fine for two players and hopeless for more: with four
## in the session, two of them landed on the same slot 65% of the time, and the
## whole point of the slot is that nobody starts inside anybody else. Ranking
## the roster gives a unique slot each, and because every peer holds the same
## roster and sorts it the same way, they all work out the same answer without
## being told.
func spawn_slot() -> int:
	if not active:
		return 0
	if is_host or my_id == 1:
		return 0
	var ids: Array = roster.keys()
	ids.sort()
	var rank := 0
	for id in ids:
		if int(id) == 1:
			continue                    # the host always has slot 0
		rank += 1
		if int(id) == my_id:
			return rank
	return 1

## Where that slot puts you. Laid out to both sides of the leader rather than
## all to starboard, so a full session is a formation rather than a queue
## stretching half a kilometre off one wing.
func spawn_offset() -> Vector3:
	var k := spawn_slot()
	if k == 0:
		return Vector3.ZERO
	var wing: float = 1.0 if k % 2 == 1 else -1.0
	var rankf := float(int((k + 1) / 2.0))
	return Vector3(wing * rankf * 90.0, -rankf * 24.0, rankf * 70.0)

## Called by the local player when it looses a store.
func report_fire(weapon: String, xf: Transform3D, vel: Vector3) -> void:
	if active:
		rpc("net_fire", my_id, weapon, xf.origin, xf.basis.get_rotation_quaternion(), vel)

# ------------------------------------------------------------ the match itself
## True on a client in a session: what the host simulates -- the AI, the
## armour, the strike waves, the score -- is only pictured here.
static func mirroring() -> bool:
	return Sim.net != null and Sim.net.active and not Sim.net.is_host

## Which match this is. The host counts up every time it starts one, so a
## restart of the same mode reaches the clients as well as a change of mode
## does: comparing the mode's name, which is all that was sent, a host that
## restarted a conquest left everyone else in the old one, and a host that
## picked another mode from the pause menu told nobody at all.
var match_gen := 0

# ---------------------------------------------------------------- sides
## This machine's side, absolute: 0 is BLUE, the host's side; 1 is RED, the
## side against it. The host is always BLUE.
##
## Every machine simulates in its own frame, where 0 is its own player's side
## -- which is what every page, every AI and every piece of scoring here was
## written to assume, in a couple of hundred places. A RED player's machine is
## the same game with the two sides swapped, so instead of teaching all of it
## about a second "us", the swap is done once, at the wire: whatever side a
## packet names is turned into this machine's frame on the way in and back on
## the way out (`lt`). The host's frame is the absolute one.
var side := 0

## A side between this machine's frame and the absolute one; its own inverse.
func lt(t: int) -> int:
	if side == 1 and (t == 0 or t == 1):
		return 1 - t
	return t

## The faction this machine's side fights with: the host's bloc for BLUE, the
## other one for RED, whatever aeroplane happens to be picked in the hangar.
func side_faction(mine: String) -> String:
	if not active or roster.is_empty():
		return mine
	var host_jet := String(roster.get(1, {}).get("jet", Sim.selected_jet))
	var host_bloc := JetSpec.bloc_of(host_jet)
	var want_nato: bool = (host_bloc == "nato") == (side == 0)
	var mine_nato: bool = JetSpec.bloc_of(Sim.selected_jet) == "nato"
	if mine_nato == want_nato:
		return mine
	return "usa" if want_nato else "russia"

## The same, for code that only has `Sim`.
static func local_team(t: int) -> int:
	if Sim.net != null and Sim.net.active:
		return Sim.net.lt(t)
	return t

## The side this player chose: 0 BLUE, 1 RED -- the same name on every screen,
## the host's included. `side` above is what that comes to in the host's
## frame (it is the same as this for the host, whose frame it is).
var abs_side := 0

## The host's own choice, as everyone knows it from the roster.
func host_abs() -> int:
	if is_host:
		return abs_side
	return int(roster.get(1, {}).get("team", 0))

## A player's side in this machine's frame, from his choice in the roster.
func peer_team(id: int) -> int:
	return lt(int(roster.get(id, {}).get("team", 0)) ^ host_abs())

## Choose a side, BLUE or RED. Anyone may, the host included, at any time; it
## is announced, and every machine whose relation to the host's side changes
## with it turns its frame over (`_flip_frame`).
func set_side(s: int) -> void:
	abs_side = clampi(s, 0, 1)
	if roster.has(my_id):
		roster[my_id]["team"] = abs_side
		if active:
			rpc("net_announce", my_id, String(roster[my_id].get("jet", "")), abs_side,
				String(roster[my_id].get("name", "")))
	_recompute_side()
	roster_changed.emit()

## Players on each side, by name: for the screens that ask which to join.
func side_counts() -> Array:
	var out := [0, 0]
	for id in roster:
		out[clampi(int(roster[id].get("team", 0)), 0, 1)] += 1
	return out

func _recompute_side() -> void:
	var now: int = 0 if is_host else (abs_side ^ host_abs())
	if now != side:
		side = now
		_flip_frame()
	_retag_players()

## Every other player's ghost on the side it is now in this frame.
func _retag_players() -> void:
	for id in ghosts:
		if is_instance_valid(ghosts[id]):
			(ghosts[id] as Aircraft).team = peer_team(id)
	for id in veh_ghosts:
		if is_instance_valid(veh_ghosts[id]):
			(veh_ghosts[id] as Tank).team = peer_team(id)
	for id in foot_ghosts:
		var g: Variant = foot_ghosts[id]
		if is_instance_valid(g):
			var nm: NetMan = (g as Node).get_node_or_null("Man") as NetMan
			if nm != null:
				nm.team = peer_team(id)

## This machine's side and the host's have changed relation: what was "ours"
## here is "theirs". The host's pictures are let go of and described again in
## the new frame; what is counted -- sectors, kills, tickets -- is swapped now
## rather than at the next packet.
func _flip_frame() -> void:
	if world == null:
		return
	_free_all(ai_ghosts)
	units.clear(true)
	ai_kinds.clear()
	if active and not is_host:
		rpc_id(1, "net_resync")
	ships.side_fleet()
	for z in world.get_tree().get_nodes_in_group("zones"):
		if is_instance_valid(z) and int(z.owner_team) in [0, 1]:
			z.owner_team = 1 - int(z.owner_team)
	var m = world.get("mode")
	if m != null and is_instance_valid(m):
		var k0 = m.kills.get(0, 0)
		m.kills[0] = m.kills.get(1, 0)
		m.kills[1] = k0
		var t0 = m.tickets.get(0, 0)
		m.tickets[0] = m.tickets.get(1, 0)
		m.tickets[1] = t0

## The generation this client last loaded, so a repeat of the same message
## (a join racing a restart) does not start it twice.
var _gen_loaded := -1
## Host: the mode of the match running now, as the hangar named it. A vehicle
## start runs as "ramp" underneath, which is not what a joiner should load.
var running_mission := ""

## Host: a match has just been started; everybody else starts it too.
func announce_match(mission: String) -> void:
	if not active or not is_host:
		return
	match_gen += 1
	running_mission = mission
	lobby_mission = mission
	rpc("net_match", mission, match_gen, match_settings())
	rpc("net_lobby_mission", mission)

## What a joiner needs besides the mode's name to build the same match: which
## town the street fight is in, how many a side and the kill goal.
func match_settings() -> Dictionary:
	return {"town": CqbMatch.town, "us": CqbMatch.size_us, "them": CqbMatch.size_them,
		"goal": CqbMatch.kill_goal}

@rpc("authority", "call_remote", "reliable")
func net_match(mission: String, gen: int, cfg: Dictionary) -> void:
	if is_host or world == null:
		return
	if gen == _gen_loaded:
		return
	_gen_loaded = gen
	match_gen = gen
	CqbMatch.town = int(cfg.get("town", CqbMatch.town))
	CqbMatch.size_us = int(cfg.get("us", CqbMatch.size_us))
	CqbMatch.size_them = int(cfg.get("them", CqbMatch.size_them))
	CqbMatch.kill_goal = int(cfg.get("goal", CqbMatch.kill_goal))
	Sim.report("host started %s" % mission, Sim.Ev.INFO)
	world.session.start_from_host.call_deferred(mission)

## Everything this machine was holding for the last match, let go of as the
## next one starts. The AI the host was flying, the armour and men it was
## running and other players' vehicles are all built again from the next
## packets; left alone they hung frozen over the new match, because the
## mission sweep rightly does not touch what the network layer owns.
func match_reset() -> void:
	for d in [ai_ghosts, veh_ghosts, foot_ghosts]:
		_free_all(d)
	units.clear(true)
	ai_kinds.clear()
	_ai_seen.clear()
	# A client that started again on its own -- taking an aeroplane from the
	# deploy screen rebuilds its copy of the match -- has just thrown away
	# every picture, and the host only describes a unit once. Ask again.
	if active and not is_host:
		rpc_id(1, "net_resync")

@rpc("any_peer", "call_remote", "reliable")
func net_resync() -> void:
	if is_host:
		units.resend()
		_ai_seen.clear()

## Host: the match's result, so it ends on every screen at once and for the
## same reason rather than whenever each copy of the count got there.
func announce_finish(win: bool, text: String) -> void:
	if active and is_host:
		rpc("net_finish", win, text)

@rpc("authority", "call_remote", "reliable")
func net_finish(win: bool, text: String) -> void:
	if is_host or world == null:
		return
	var m = world.get("mode")
	if m != null and is_instance_valid(m):
		# the host's result is BLUE's: a RED player won what BLUE lost
		m.finish_from_host(win if side == 0 else not win, text)

## The kill count, which in a street fight is the score.
@rpc("authority", "call_remote", "unreliable_ordered")
func net_kills(k_us: int, k_them: int) -> void:
	if is_host or world == null:
		return
	var m = world.get("mode")
	if m != null and is_instance_valid(m):
		m.kills[lt(0)] = k_us
		m.kills[lt(1)] = k_them

## One line of the kill feed, on every screen. `skip` is a peer that already
## wrote it for itself.
func broadcast_feed(k: String, kt: int, v: String, vt: int, w: String, head: bool,
		skip := 0) -> void:
	if not active or not is_host:
		return
	for pid in multiplayer.get_peers():
		if pid != skip:
			rpc_id(pid, "net_feed", k, kt, v, vt, w, head)

@rpc("authority", "call_remote", "reliable")
func net_feed(k: String, kt: int, v: String, vt: int, w: String, head: bool) -> void:
	Sim.kill(k, lt(kt), v, lt(vt), w, head)

# ---------------------------------------------------- players on foot, as men
## Damage that landed on somebody else's man on foot: it goes to his machine.
func report_man_hit(peer: int, amount: float, cause: String, head: bool,
		from: Node = null) -> void:
	if not active:
		return
	var by := KillFeed.name_of(from) if from != null and is_instance_valid(from) else ""
	if peer == my_id:
		net_man_hit(peer, amount, cause, head, by)
	elif is_host:
		rpc_id(peer, "net_man_hit", peer, amount, cause, head, by)
	else:
		rpc_id(1, "net_man_hit", peer, amount, cause, head, by)

@rpc("any_peer", "call_remote", "reliable")
func net_man_hit(peer: int, amount: float, cause: String, head: bool, by: String) -> void:
	if world == null:
		return
	if peer != my_id:
		if is_host:
			rpc_id(peer, "net_man_hit", peer, amount, cause, head, by)
		return
	var w = world.get("walker")
	if w == null or not is_instance_valid(w) or not world.get("on_foot") or w.dead:
		return
	w._last_head = head
	w.set_meta("net_by", by)
	w.take_hit(amount, null)
	w.last_cause = cause

## A player on this machine went down in a street fight. The host counts it.
func report_down(victim: String, killer: String, cause: String, head := false) -> void:
	if not active:
		return
	if is_host:
		net_down(victim, killer, cause, head, side)
	else:
		rpc_id(1, "net_down", victim, killer, cause, head, side)

@rpc("any_peer", "call_remote", "reliable")
func net_down(victim: String, killer: String, cause: String, head: bool, vside := 0) -> void:
	if not is_host or world == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var fight = world.get("cqb")
	if fight != null and is_instance_valid(fight) and sender != 0:
		fight.remote_down(vside)
	if sender != 0:
		Sim.kill(killer, 1 - vside, victim, vside, cause, head)
	broadcast_feed(killer, 1 - vside, victim, vside, cause, head, sender)
