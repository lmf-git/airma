class_name NetUnits
extends Node
## The host's units over the network.
##
## What the host simulates on the ground and is not a sector's garrison: the
## men of a street fight, the armour that drives about in it, and a strike's
## columns and shipping. Keyed by a number the host hands out the first time it
## publishes each one; a client builds a picture of each from the roster and
## moves it from the state packets. Every hit a client lands on a picture goes
## back to the host, which decides, and the death comes back in the next packet.
##
## A child of `NetLink` (as "Units"), so its RPCs have the same path on every
## peer.

var link: NetLink
var by_key := {}                # key -> Node: the host's real ones, a client's pictures
var _seen := {}                 # host: keys every client has been told about
var _fate := {}                 # host: key -> 2 head shot, 1 killed
var _shots := {}                # client: key -> last shot count seen
var _seq := 0
## Host: the peer whose reported hit is being applied, so a kill it makes is
## credited to the man who made it.
var crediting := 0
## Main-gun and machine-gun rounds drawn for vehicle pictures, for the harness.
var vehicle_rounds_drawn := Vector2i.ZERO

func _init(l: NetLink) -> void:
	link = l
	name = "Units"

## Let go of everything: a client's pictures are freed, the host's units are
## only forgotten (they are the match's, and the sweep has them).
func clear(free_pictures: bool) -> void:
	if free_pictures:
		for k in by_key:
			if is_instance_valid(by_key[k]):
				(by_key[k] as Node).queue_free()
	by_key.clear()
	_seen.clear()
	_fate.clear()
	_shots.clear()

## Host: describe every unit again, to a client that has thrown its pictures away.
func resend() -> void:
	_seen.clear()

func _key(n: Node) -> int:
	if not n.has_meta("net_unit"):
		_seq += 1
		n.set_meta("net_unit", _seq)
		if n is Soldier:
			var key := _seq
			(n as Soldier).died.connect(func(_w, _k, head) -> void:
				_fate[key] = 2 if head else 1)
	return int(n.get_meta("net_unit"))

func _kind(n: Node) -> String:
	if n is Soldier:
		return "man:%s:%s" % [(n as Soldier).kit, (n as Soldier).launcher]
	if n is Tank:
		return "tank:%s" % (n as Tank).kind
	if n is Ship:
		return "ship:%s" % (n as Ship).kind
	return ""

func _host_units() -> Array:
	var world := link.world
	var out: Array = []
	var fight = world.get("cqb")
	if fight != null and is_instance_valid(fight):
		for s in fight.soldiers:
			if is_instance_valid(s) and (s as Soldier).alive:
				out.append(s)
	for v in world.get_tree().get_nodes_in_group("vehicles"):
		var t := v as Tank
		if t == null or not is_instance_valid(t) or t.is_in_group("remote") \
				or t.has_meta("net_id") or t.has_meta("zone_asset") \
				or t == world.get("tank"):
			continue
		if t.ai or t.has_meta("strike"):
			out.append(t)
	for s2 in world.get_tree().get_nodes_in_group("ships"):
		if is_instance_valid(s2) and s2 is Ship and s2.has_meta("strike") \
				and (s2 as Ship).fleet_idx < 0:
			out.append(s2)
	return out

## Host side, ten times a second: units that have gone, units that are new,
## and the state of all of them.
func publish() -> void:
	var now := {}
	for n in _host_units():
		now[_key(n)] = n
	var gone := PackedInt32Array()
	var how := PackedByteArray()
	for key in _seen.keys():
		if not now.has(key):
			gone.append(key)
			how.append(int(_fate.get(key, 0)))
			_seen.erase(key)
			_fate.erase(key)
			by_key.erase(key)
	if gone.size() > 0:
		rpc("net_units_gone", gone, how)
	var nk := PackedInt32Array()
	var nkind := PackedStringArray()
	var nteam := PackedInt32Array()
	var nname := PackedStringArray()
	var keys := PackedInt32Array()
	var pos := PackedVector3Array()
	var ang := PackedFloat32Array()
	var flags := PackedByteArray()
	# rounds fired, main gun in the low half and machine gun in the high
	var fire := PackedInt32Array()
	for key in now:
		var n: Node3D = now[key]
		by_key[key] = n
		link.launches.watch(n)
		if not _seen.has(key):
			_seen[key] = true
			nk.append(key)
			nkind.append(_kind(n))
			nteam.append(int(n.get("team")))
			nname.append(String(n.get("callsign")) if n is Soldier else String(n.name))
		keys.append(key)
		pos.append(n.global_position)
		var f := 0
		if n is Soldier:
			var s := n as Soldier
			ang.append(s.yaw)
			ang.append(s.pitch)
			ang.append(float(s.shots % 256))
			f = 1 | (2 if s.crouching else 0) | (4 if s.state == Soldier.FIGHT else 0)
		elif n is Tank:
			var t := n as Tank
			ang.append(t.rotation.y)
			ang.append(t.turret_yaw)
			ang.append(t.turret_pitch)
			f = 1 if t.alive else 0
			fire.resize(keys.size())
			fire[keys.size() - 1] = (t.shots_main & 0xFFFF) | ((t.shots_coax & 0x7FFF) << 16)
		else:
			var sh := n as Ship
			ang.append(sh.heading)
			ang.append(sh.health)
			ang.append(sh.sink_fraction() if sh.is_sinking() else 0.0)
			f = (1 if sh.alive else 0) | (2 if sh.is_sinking() else 0)
		flags.append(f)
	if nk.size() > 0:
		rpc("net_units_roster", nk, nkind, nteam, nname)
	if keys.size() > 0:
		fire.resize(keys.size())
		rpc("net_units", keys, pos, ang, flags, fire)

@rpc("authority", "call_remote", "reliable")
func net_units_roster(keys: PackedInt32Array, kinds: PackedStringArray,
		teams: PackedInt32Array, names: PackedStringArray) -> void:
	var world := link.world
	if link.is_host or world == null:
		return
	for i in keys.size():
		var key := keys[i]
		if by_key.has(key) and is_instance_valid(by_key[key]):
			continue
		var bits := kinds[i].split(":")
		var n: Node3D = null
		match bits[0]:
			"man":
				var s := Soldier.new()
				s.team = link.lt(teams[i])
				s.kit = bits[1] if bits.size() > 1 else "carbine"
				s.launcher = bits[2] if bits.size() > 2 else ""
				s.callsign = names[i]
				s.name = names[i]
				s.ghost = true
				var fight = world.get("cqb")
				if fight != null and is_instance_valid(fight):
					s.arena = fight
					fight.add_child(s)
					fight.adopt_ghost(s)
				else:
					world.add_child(s)
				n = s
			"tank":
				var t := Tank.new()
				t.setup(link.lt(teams[i]), bits[1] if bits.size() > 1 else "m1a2")
				t.name = names[i]
				t.make_picture()
				world.add_child(t)
				n = t
			"ship":
				var sh := Ship.new()
				sh.setup(bits[1] if bits.size() > 1 else "cargo", link.lt(teams[i]))
				sh.name = names[i]
				sh.ghost = true
				sh.set_meta("strike", true)
				world.add_child(sh)
				n = sh
		if n == null:
			continue
		n.set_meta("net_unit", key)
		n.set_meta("t_rx", 0)
		n.visible = false
		by_key[key] = n

@rpc("authority", "call_remote", "unreliable_ordered")
func net_units(keys: PackedInt32Array, pos: PackedVector3Array, ang: PackedFloat32Array,
		flags: PackedByteArray, fire := PackedInt32Array()) -> void:
	if link.is_host or link.world == null:
		return
	for i in keys.size():
		var u := NetLink.live(by_key, keys[i]) as Node3D
		if u == null:
			continue
		var first: bool = int(u.get_meta("t_rx", 0)) == 0
		u.set_meta("t_rx", Time.get_ticks_msec())
		u.set_meta("target_pos", pos[i])
		if first:
			u.global_position = pos[i]
			u.visible = true
		var a0: float = ang[i * 3]
		var a1: float = ang[i * 3 + 1]
		var a2: float = ang[i * 3 + 2]
		var f: int = flags[i]
		if u is Soldier:
			var s := u as Soldier
			s.set_meta("net_yaw", a0)
			s.pitch = a1
			s.crouching = (f & 2) != 0
			s.state = Soldier.FIGHT if (f & 4) != 0 else Soldier.ROAM
			var shots := int(a2)
			var was: int = int(_shots.get(keys[i], shots))
			_shots[keys[i]] = shots
			if shots != was and not first:
				s.ghost_shot()
		elif u is Tank:
			var t := u as Tank
			t.set_meta("target_rot", Quaternion(Vector3.UP, a0))
			t.turret_yaw = a1
			t.turret_pitch = a2
			if (f & 1) == 0 and t.alive:
				t.apply_damage(1.0e6)
			elif i < fire.size():
				_vehicle_shots(keys[i], t, fire[i], first)
		elif u is Ship:
			var sh := u as Ship
			sh.net_apply(pos[i], a0, a1, 0.0, 0.0, 0.0,
				(f & 1) | ((f & 2)) | (int(clampf(a2, 0.0, 1.0) * 255.0) << 8))

@rpc("authority", "call_remote", "reliable")
func net_units_gone(keys: PackedInt32Array, how: PackedByteArray) -> void:
	if link.is_host or link.world == null:
		return
	for i in keys.size():
		var n := NetLink.live(by_key, keys[i])
		by_key.erase(keys[i])
		_shots.erase(keys[i])
		if n == null:
			continue
		if n is Soldier and how[i] > 0:
			(n as Soldier).ghost_die(how[i] == 2)
		else:
			n.queue_free()

## What a vehicle picture has fired since the last packet, drawn. A packet
## comes ten times a second and a machine gun fires about as often, so a few
## rounds can be owed at once; more than that is a packet lost, and is not
## made up all at once.
func _vehicle_shots(key: int, t: Tank, packed: int, first: bool) -> void:
	var main := packed & 0xFFFF
	var coax := (packed >> 16) & 0x7FFF
	var was: Variant = _shots.get(key)
	_shots[key] = Vector2i(main, coax)
	if first or was == null or not (was is Vector2i):
		return
	var dm: int = (main - (was as Vector2i).x) & 0xFFFF
	var dc: int = (coax - (was as Vector2i).y) & 0x7FFF
	for i in mini(dm, 2):
		t.ghost_fire(link.world, true)
		vehicle_rounds_drawn.x += 1
	for i in mini(dc, 3):
		t.ghost_fire(link.world, false)
		vehicle_rounds_drawn.y += 1

## Client side, every physics tick: each picture eased onto where it was said
## to be.
func tick(delta: float) -> void:
	if link.is_host:
		return
	var k: float = clampf(delta * 10.0, 0.0, 1.0)
	for key in by_key:
		var u := NetLink.live(by_key, key) as Node3D
		if u == null or not u.has_meta("target_pos") or u is Ship:
			continue
		var want: Vector3 = u.get_meta("target_pos")
		if u is Tank:
			var rot: Quaternion = u.get_meta("target_rot", Quaternion.IDENTITY)
			u.global_transform = Transform3D(Basis(
				u.global_transform.basis.get_rotation_quaternion().slerp(rot, k)),
				u.global_position.lerp(want, k))
		# a man is moved by his own `_process`, so his legs see the step

## A client hit one of the host's units.
func report_hit(n: Node, amount: float, cause: String, head := false) -> void:
	if not link.active or not n.has_meta("net_unit"):
		return
	rpc_id(1, "net_unit_hit", int(n.get_meta("net_unit")), amount, cause, head)

@rpc("any_peer", "call_remote", "reliable")
func net_unit_hit(key: int, amount: float, cause: String, head: bool) -> void:
	if not link.is_host or link.world == null:
		return
	var n := NetLink.live(by_key, key)
	if n == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var from: Node = null
	for m in link.world.get_tree().get_nodes_in_group("net_men"):
		if is_instance_valid(m) and int(m.peer) == sender:
			from = m
	if from == null:
		from = NetLink.live(link.veh_ghosts, sender)
	var was_cause := KillFeed.cause
	KillFeed.cause = cause
	crediting = sender
	if n is Soldier:
		(n as Soldier)._last_head = head
		(n as Soldier).take_hit(amount, from)
	elif n is Tank:
		(n as Tank).apply_damage(amount)
	elif n is Ship:
		(n as Ship).take_hit(amount, null)
	crediting = 0
	KillFeed.cause = was_cause

## Host: a kill made by somebody on another machine, for his streaks and score.
func credit_kill(peer: int, victim: String, head: bool) -> void:
	if link.active and link.is_host and peer > 1:
		rpc_id(peer, "net_credit", victim, head)

@rpc("authority", "call_remote", "reliable")
func net_credit(victim: String, head: bool) -> void:
	var fight = link.world.get("cqb") if link.world != null else null
	if fight != null and is_instance_valid(fight):
		fight.credit_kill(victim, head)
