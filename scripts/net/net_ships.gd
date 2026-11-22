class_name NetShips
extends Node
## Ships over the network: the fleet's pose and state, who has the conn of a
## hull, and the rounds and hits that pass between a client and the host.
##
## Ships do not need a spawn roster. Every peer builds the same fleet from the
## same plan at load, so a hull is addressed by its index in that plan and the
## host only has to say where it is and what state it is in. Clients hold theirs
## as ghosts: posed, not simulated, so the two ends cannot diverge.
##
## A child of `NetLink` (as "Ships"), so its RPCs have the same path on every
## peer.

var link: NetLink
## Fleet index this peer has the conn of, -1 none.
var conn := -1
var _acc := 0.0

func _init(l: NetLink) -> void:
	link = l
	name = "Ships"

func reset() -> void:
	set_ghosts(false)
	conn = -1

## A client hands the whole fleet over to the host. They are built identically
## on both ends at load, long before anyone connects, so this flips them rather
## than trying to decide at construction time.
func set_ghosts(on: bool) -> void:
	for sh in _fleet():
		sh.ghost = on

## Every ship afloat or sinking, as `Ship`.
func _fleet() -> Array[Ship]:
	var out: Array[Ship] = []
	if link.world == null:
		return out
	for n in link.world.get_tree().get_nodes_in_group("ships"):
		if is_instance_valid(n) and n is Ship:
			out.append(n as Ship)
	return out

func by_index(i: int) -> Ship:
	for sh in _fleet():
		if sh.fleet_idx == i:
			return sh
	return null

## Each fleet ship's team in this machine's frame (see `NetLink.side`). The
## plan's own team is kept on the hull the first time, as the absolute one.
func side_fleet() -> void:
	for sh in _fleet():
		if sh.fleet_idx < 0:
			continue
		if not sh.has_meta("abs_team"):
			sh.set_meta("abs_team", sh.team)
		sh.team = link.lt(int(sh.get_meta("abs_team")))

@rpc("authority", "call_remote", "unreliable_ordered")
func net_ships(idx: PackedInt32Array, pos: PackedVector3Array,
		yaw: PackedFloat32Array, hp: PackedFloat32Array,
		dmg: PackedFloat32Array, flags: PackedInt32Array) -> void:
	if link.is_host or link.world == null:
		return
	link.rx += 1
	var seen := {}
	for i in idx.size():
		seen[idx[i]] = true
		var sh := by_index(idx[i])
		if sh == null:
			continue
		sh.net_apply(pos[i], yaw[i], hp[i], dmg[i * 3], dmg[i * 3 + 1],
			dmg[i * 3 + 2], flags[i])
	# A hull the host has stopped publishing has gone to the bottom and been
	# cleaned up there. A client never runs the sinking clock itself, so without
	# this it keeps every wreck it has ever seen: measured, a host with seven
	# ships afloat and a client holding ten.
	for s2 in _fleet():
		if s2.fleet_idx >= 0 and not seen.has(s2.fleet_idx) and not s2.alive:
			s2.queue_free()

## The conn changes hands. The host stops letting the AI captain steer that
## hull and starts taking its wheel and telegraph from the peer instead.
@rpc("any_peer", "call_local", "reliable")
func net_ship_conn(i: int, taken: bool) -> void:
	if not link.is_host:
		return
	var sh := by_index(i)
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
	if not link.is_host:
		return
	var sh := by_index(i)
	if sh == null or sh.remote_conn != multiplayer.get_remote_sender_id():
		return
	sh.net_orders(helm, telegraph, yaw, pitch)

## A request to shoot, and the round everyone else sees. `what` is 0 for the
## main battery and 1 for the tubes.
@rpc("any_peer", "call_remote", "reliable")
func net_ship_fire(i: int, what: int, yaw: float, pitch: float) -> void:
	if not link.is_host:
		return
	var sh := by_index(i)
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
	if link.is_host or link.world == null:
		return
	var sh := by_index(i)
	if sh == null:
		return
	sh.show_shot(yaw, pitch)

## Host: a hull's battery fired; every other screen draws it.
func share_shot(i: int, yaw: float, pitch: float) -> void:
	if link.active and link.is_host:
		rpc("net_ship_shot", i, yaw, pitch)

func request_fire(i: int, what: int, yaw: float, pitch: float) -> void:
	if not link.active or i < 0:
		return
	rpc_id(1, "net_ship_fire", i, what, yaw, pitch)

func take_conn(i: int, taken: bool) -> void:
	if not link.active:
		return
	conn = i if taken else -1
	if link.is_host:
		var sh := by_index(i)
		if sh != null:
			sh.remote_conn = 0
			sh.ai = not taken
		return
	rpc_id(1, "net_ship_conn", i, taken)

@rpc("any_peer", "call_remote", "reliable")
func net_ship_hit(i: int, amount: float) -> void:
	if not link.is_host:
		return
	var sh := by_index(i)
	if sh != null and sh.alive:
		sh.take_hit(amount, null)

## A client's weapon reached a hull the host owns. The client's copy is a
## picture and has no standing to decide whether it just sank.
func report_damage(sh: Node, amount: float) -> void:
	if not link.active or not (sh is Ship):
		return
	if sh.has_meta("net_unit") and not link.is_host:
		link.units.report_hit(sh, amount, "")
		return
	var i: int = (sh as Ship).fleet_idx
	if i < 0:
		return
	if link.is_host:
		(sh as Ship).take_hit(amount, null)
	else:
		rpc_id(1, "net_ship_hit", i, amount)

## Host side, every send: one packet for the whole fleet, five times a second.
## A ship is slow and there are a dozen of them, so this is cheaper than
## treating each hull as its own replicated actor.
func publish(dt: float) -> void:
	_acc += dt
	if _acc < 0.2:
		return
	_acc = 0.0
	var idx := PackedInt32Array()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var hp := PackedFloat32Array()
	var dmg := PackedFloat32Array()
	var flags := PackedInt32Array()
	for sh in _fleet():
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
		link.tx += 1
		rpc("net_ships", idx, pos, yaw, hp, dmg, flags)

## Client holding the conn of a ship: the orders go over, the hull comes back.
## True while it is, so nothing else of this player's is sent.
func send_orders() -> bool:
	if conn < 0 or link.is_host:
		return false
	var sh := by_index(conn)
	if sh != null and sh.occupied:
		link.tx += 1
		rpc_id(1, "net_ship_orders", conn, sh.helm, sh.telegraph,
			sh.aim_yaw, sh.aim_pitch)
	return true
