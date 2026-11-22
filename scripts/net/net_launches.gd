class_name NetLaunches
extends Node
## Rounds that fly far enough to matter, shown on every machine.
##
## Every round a vehicle or a site fires -- a tank's shell, a rocket battery's
## ripple, a SAM, a cruise or ballistic missile -- and a man's grenades, rockets
## and mortar bombs, and the strikes he calls. Only the machine that owns the
## launcher simulates the real one; everyone else is sent where it left, how
## fast, and what it is after, and flies a copy of it that homes, warns and goes
## off the same way and hurts nothing. Without this a client was shot down by a
## battery that never visibly fired, and a rocket ripple landed out of nowhere.
##
## A child of `NetLink` (as "Launches"), so its RPCs have the same path on every
## peer.

var link: NetLink
## Launches shared from here and copies drawn here, for the harness.
var sent := 0
var drawn := 0

func _init(l: NetLink) -> void:
	link = l
	name = "Launches"

## Start sharing what this launcher fires. Safe to call every frame.
func watch(t: Node) -> void:
	if not is_instance_valid(t) or t.has_meta("net_watch") or not t.has_signal("store_released"):
		return
	t.set_meta("net_watch", true)
	t.store_released.connect(func(r: Node) -> void: share(t, r))

## Who fired, as every machine can name it.
func _who_of(n: Node) -> String:
	if not is_instance_valid(n):
		return "x"
	if n.has_meta("net_unit"):
		return "u:%d" % int(n.get_meta("net_unit"))
	if n.has_meta("zone_asset"):
		var k: Array = n.get_meta("zone_asset")
		return "z:%s:%d" % [String(k[0]), int(k[1])]
	var world := link.world
	if n == world.get("tank") or n == world.get("player") or n == world.get("walker"):
		return "p:%d" % link.my_id
	if n.is_in_group("bandits") and not n.is_in_group("remote"):
		return "a:%d" % NetLink.ai_key(n)
	return "x"

func _who_node(who: String) -> Node3D:
	var bits := who.split(":")
	match bits[0]:
		"u":
			return NetLink.live(link.units.by_key, int(bits[1])) as Node3D
		"z":
			return link.zone_asset(bits[1], int(bits[2]))
		"a":
			return NetLink.live(link.ai_ghosts, int(bits[1])) as Node3D
		"p":
			var pid := int(bits[1])
			var v := NetLink.live(link.veh_ghosts, pid) as Node3D
			return v if v != null else NetLink.live(link.ghosts, pid) as Node3D
	return null

## What a round is after, as every machine can find it.
func _target_ref(n: Variant) -> Dictionary:
	if n == null or not is_instance_valid(n) or not (n is Node3D):
		return {}
	var t := n as Node3D
	if t.has_meta("net_unit"):
		return {"u": int(t.get_meta("net_unit"))}
	if t.has_meta("net_id"):
		return {"p": int(t.get_meta("net_id"))}
	if t == link.world.get("player") or t == link.world.get("tank"):
		return {"p": link.my_id}
	if t.has_meta("net_ai"):
		return {"a": int(t.get_meta("net_ai"))}
	if t.is_in_group("bandits") and not t.is_in_group("remote"):
		return {"a": NetLink.ai_key(t)}
	if t.has_meta("zone_asset"):
		var k: Array = t.get_meta("zone_asset")
		return {"z": String(k[0]), "zi": int(k[1]), "m": t.global_position}
	if t.is_in_group("satellites"):
		return {"sat": String(t.name), "m": t.global_position}
	return {"m": t.global_position}

func _target_node(r: Dictionary) -> Node3D:
	var world := link.world
	if r.has("u"):
		var u := NetLink.live(link.units.by_key, int(r["u"])) as Node3D
		if u != null:
			return u
	if r.has("p"):
		var pid := int(r["p"])
		if pid == link.my_id:
			var mine: Variant = world.get("tank")
			if mine == null or not is_instance_valid(mine):
				mine = world.get("player")
			if mine != null and is_instance_valid(mine):
				return mine
		else:
			var g := _who_node("p:%d" % pid)
			if g != null:
				return g
	if r.has("a"):
		var key := int(r["a"])
		var a: Node3D = link.ai_by_key(key) if link.is_host \
			else NetLink.live(link.ai_ghosts, key) as Node3D
		if a != null:
			return a
	if r.has("z"):
		var za := link.zone_asset(String(r["z"]), int(r["zi"]))
		if za != null:
			return za
	if r.has("sat"):
		for s in world.get_tree().get_nodes_in_group("satellites"):
			if is_instance_valid(s) and String(s.name) == String(r["sat"]):
				return s
	if r.has("m"):
		# a place: a mark of its own, gone with the round
		var mk := _Mark.new()
		world.add_child(mk)
		mk.global_position = r["m"]
		return mk
	return null

## A spot on the ground for a copied round to go to: what a launcher's own
## aiming mark is on the machine that fired it.
class _Mark extends Node3D:
	var team := -1
	func _ready() -> void:
		add_to_group("no_lock")
	func hit_radius() -> float:
		return 6.0
	func is_alive() -> bool:
		return true
	func take_hit(_a: float, _f: Node = null) -> void:
		pass

## Out to everyone else: the host sends it round, a client to the host, which
## passes it on (`net_launch`).
func _send(d: Dictionary) -> void:
	sent += 1
	if link.is_host:
		rpc("net_launch", d)
	else:
		rpc_id(1, "net_launch", d)

## The launcher here fired `r`: tell everyone else.
func share(by: Node, r: Node) -> void:
	if not link.active or not is_instance_valid(r) or r.get("harmless") == true:
		return
	var tm: int = 1
	if is_instance_valid(by):
		tm = int(by.get("team")) if "team" in by else (int(by.get("side")) if "side" in by else 1)
	var d := {"by": _who_of(by), "team": link.lt(tm)}
	if r is Aircraft.Shell:
		var sh := r as Aircraft.Shell
		d["k"] = "shell"
		d["o"] = sh.global_position
		d["v"] = sh.vel
		d["b"] = sh.blast
		d["r"] = sh.rocket
		d["d"] = sh.drag
	elif r is Missile:
		var m := r as Missile
		d["k"] = "missile"
		d["w"] = m.wid
		d["o"] = m.global_position
		d["q"] = m.global_transform.basis.get_rotation_quaternion()
		d["v"] = m.vel
		d["t"] = _target_ref(m.target)
		var prog: Array = []
		for p in m.programmed:
			if p is Vector3:
				prog.append(p)
			elif is_instance_valid(p) and p is Node3D:
				prog.append((p as Node3D).global_position)
		d["prog"] = prog
	elif r is Icbm:
		var ic := r as Icbm
		d["k"] = "icbm"
		d["w"] = ic.wid
		d["o"] = ic.global_position
		var marks: Array = []
		for mk in ic.marks:
			if mk is Vector3:
				marks.append(mk)              # already a direction on the planet
			elif is_instance_valid(mk) and mk is Node3D:
				var gp: Vector3 = (mk as Node3D).global_position
				marks.append(Sim.chart_to_dir(gp.x, gp.z))
		d["marks"] = marks
	else:
		return
	_send(d)

## A man's round -- a grenade, a rocket off the shoulder, a 40 mm, a mortar
## bomb -- sent to everyone else as it leaves, the way a vehicle's are. Only
## his bullets used to go: a grenade or a flashbang he threw went off on his
## own screen and nowhere else.
func share_round(r: Node) -> void:
	if not link.active or not is_instance_valid(r) or r.get("harmless") == true \
			or r.get("picture") == true:
		return
	var d := {}
	if r is Firearm.Frag:
		var f := r as Firearm.Frag
		d = {"k": "frag", "o": f.global_position, "v": f.vel, "fuse": f.fuse,
			"flash": f.flash, "team": link.lt(f.team)}
	elif r is Firearm.Rocket:
		var k := r as Firearm.Rocket
		d = {"k": "rkt", "o": k.global_position, "v": k.vel, "fall": k.fall,
			"blast": k.blast, "arm": k.arm, "small": k.small, "life": k.life,
			"team": link.lt(k.team)}
	elif r is MortarRound:
		var mr := r as MortarRound
		d = {"k": "mortar", "from": mr.from, "to": mr.to, "flight": mr.flight,
			"delay": mr.delay}
	else:
		return
	d["by"] = _who_of(link.world.get("walker"))
	_send(d)

## A strike called here, for everyone else to see: what it was, where, and
## where the man who called it was standing and facing -- which is where the
## run comes in from. See `Killstreaks.call_picture`.
func share_streak(which: String, at: Vector3, x: Dictionary) -> void:
	if not link.active:
		return
	_send({"k": "streak", "call": which, "at": at, "x": x, "team": link.lt(0),
		"by": "p:%d" % link.my_id})

## The ATTACK HELICOPTER for a player on another machine is flown by the host,
## on that player's side, so it is one aircraft on every screen (it reaches
## the others as AI, like any other the host flies).
func request_heli(back: Vector3) -> void:
	if link.active and not link.is_host:
		rpc_id(1, "net_heli", back, link.side)

@rpc("any_peer", "call_remote", "reliable")
func net_heli(back: Vector3, host_side: int) -> void:
	if not link.is_host or link.world == null:
		return
	var fight = link.world.get("cqb")
	if fight != null and is_instance_valid(fight):
		fight.streaks.spawn_streak_heli(host_side, back)

@rpc("any_peer", "call_remote", "reliable")
func net_launch(d: Dictionary) -> void:
	var world := link.world
	if world == null:
		return
	if link.is_host:
		var sender := multiplayer.get_remote_sender_id()
		for pid in multiplayer.get_peers():
			if pid != sender:
				rpc_id(pid, "net_launch", d)
	var who := String(d.get("by", "x"))
	if who == "p:%d" % link.my_id:
		return                        # our own, passed back
	if String(d.get("k", "")) == "streak":
		var fight = world.get("cqb")
		if fight != null and is_instance_valid(fight):
			var pid := int(who.split(":")[1]) if who.begins_with("p:") else 0
			fight.streaks.call_picture(String(d["call"]), d.get("at", Vector3.ZERO), d.get("x", {}),
				link.name_of(pid), link.lt(int(d.get("team", 0))) == 0)
			drawn += 1
		return
	var by := _who_node(who)
	var team := link.lt(int(d.get("team", 1)))
	var at: Vector3 = d.get("o", Vector3.ZERO)
	var scn: Node = world
	drawn += 1
	match String(d.get("k", "")):
		"shell":
			var sh := Aircraft.Shell.new()
			sh.harmless = true
			sh.vel = d.get("v", Vector3.ZERO)
			sh.blast = float(d.get("b", 8.0))
			sh.damage = 0.0
			sh.rocket = bool(d.get("r", false))
			sh.drag = float(d.get("d", 0.0))
			sh.team = team
			sh.shooter = by
			scn.add_child(sh)
			sh.global_position = at
			var dir: Vector3 = (sh.vel as Vector3).normalized()
			Effects.muzzle_flash(scn, at, dir, 2.2 if sh.rocket else 3.4)
			Effects.dust(scn, at, 4.5)
			Sfx.play_at(scn, "launch" if sh.rocket else "boom", at, -2.0,
				1.0 if sh.rocket else 0.7, 4000.0)
		"missile":
			var tgt := _target_node(d.get("t", {}))
			var m := Missile.new()
			m.harmless = true
			var q: Quaternion = d.get("q", Quaternion.IDENTITY)
			m.launch(String(d["w"]), Transform3D(Basis(q), at), d.get("v", Vector3.ZERO),
				by, tgt)
			m.team = team
			for p in d.get("prog", []):
				m.programmed.append(p)
			scn.add_child(m)
			if tgt is _Mark:
				m.tree_exiting.connect(tgt.queue_free)
			Effects.dust(scn, at, 3.0)
			Sfx.play_at(scn, "launch", at, 0.0, 1.0, 3000.0)
		"frag":
			var fg := Firearm.Frag.new()
			fg.harmless = true
			fg.flash = bool(d.get("flash", false))
			fg.fuse = float(d.get("fuse", 2.9))
			fg.team = team
			fg.vel = d.get("v", Vector3.ZERO)
			scn.add_child(fg)
			fg.global_position = at
		"rkt":
			var rk := Firearm.Rocket.new()
			rk.harmless = true
			rk.team = team
			rk.dmg = 0.0
			rk.vel = d.get("v", Vector3.ZERO)
			rk.fall = float(d.get("fall", 3.0))
			rk.blast = float(d.get("blast", 4.6))
			rk.arm = float(d.get("arm", 0.0))
			rk.small = bool(d.get("small", false))
			rk.life = float(d.get("life", 3.5))
			scn.add_child(rk)
			rk.global_position = at
			Sfx.play_at(scn, "launch", at, -2.0 if rk.small else 2.0, 2.3 if rk.small else 1.5, 900.0)
		"mortar":
			var mo := MortarRound.new()
			mo.picture = true
			mo.from = d.get("from", Vector3.ZERO)
			mo.to = d.get("to", Vector3.ZERO)
			mo.flight = float(d.get("flight", 12.0))
			mo.delay = float(d.get("delay", 0.0))
			scn.add_child(mo)
		"icbm":
			var ic := Icbm.new()
			ic.harmless = true
			ic.wid = String(d["w"])
			ic.ws = WeaponSpec.get_spec(ic.wid)
			ic.shooter = by
			ic.team = team
			for mk in d.get("marks", []):
				ic.marks.append(mk)
			var p: Vector3 = Sim.world_to_space(at)
			ic._s = Orbit.make(p, p.normalized() * 4.0)
			scn.add_child(ic)
			ic.global_position = at
