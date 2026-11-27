class_name Killstreaks
extends RefCounted
## Killstreaks in a street fight: which ones a player has picked and earned,
## the points they cost, and every one of them called in -- the UAV, the mortar,
## the air strikes and gun runs, the gunship and the attack helicopter, the cruise
## missile and the nukes, and the rest -- with the map picks they wait on, and
## the pictures other machines draw of a strike called on one of them.
##
## Split out of `cqb.gd`, whose fight it works on through `fight`.

var fight: CqbMatch

## Everything a run of kills without dying can earn. Up to four are carried,
## chosen on the deploy screen; they are spent with 4 to 7, cheapest first.
const STREAK_POOL := [
	{"id": "uav", "name": "UAV", "at": 3,
		"note": "Every hostile on your map for thirty seconds."},
	{"id": "smoke", "name": "SMOKE BARRAGE", "at": 3,
		"note": "A thick line of smoke across a spot you pick on the map, for most of a minute. Nobody sees through it."},
	{"id": "cuav", "name": "COUNTER-UAV", "at": 4,
		"note": "Scrambles the other side's map and keeps anything of theirs out of the air for forty-five seconds."},
	{"id": "supply", "name": "SUPPLY DROP", "at": 4,
		"note": "A crate on a parachute at your mark: every magazine, both grenades and your health back, for you and your side."},
	{"id": "sentry", "name": "SENTRY TURRET", "at": 5,
		"note": "A machine gun on a tripod, set down where you stand facing the way you look. It holds that street until it is knocked out or out of ammunition."},
	{"id": "vest", "name": "BALLISTIC VEST DROP", "at": 5,
		"note": "A crate of plate carriers at your mark: half of every hit is taken by the vest until it is spent."},
	{"id": "mortar", "name": "MORTAR BARRAGE", "at": 4,
		"note": "Ten rounds walked over a spot you pick on the map."},
	{"id": "strike", "name": "AIRSTRIKE", "at": 5,
		"note": "A stick of seven along the line to your mark."},
	{"id": "dogs", "name": "ATTACK DOGS", "at": 6,
		"note": "Three military working dogs run the streets and the buildings for the nearest of theirs: the way to get somebody out of a room the air cannot see into."},
	{"id": "swarm", "name": "SWITCHBLADE SWARM", "at": 6,
		"note": "Four small kamikaze drones climb out over you, each finds one of theirs it can see in the open, and dives on him."},
	{"id": "strafe", "name": "A-10 GUN RUN", "at": 6,
		"note": "Two points on the map set a line; a pair of A-10s come down it with their guns."},
	{"id": "heli", "name": "ATTACK HELICOPTER", "at": 7,
		"note": "A gunship patrols over the town on its own for most of a minute and hunts whoever of theirs it can see, while you keep fighting."},
	{"id": "gunship", "name": "AC-130 GUNNER", "at": 7,
		"note": "You on the guns of a gunship over the town."},
	{"id": "carpet", "name": "B-2 CARPET BOMB", "at": 8,
		"note": "Two points on the map set the line; a B-2 comes over and lays a carpet along it."},
	{"id": "missile", "name": "FIRE MISSION", "at": 9,
		"note": "A launcher out of town lays rounds on your mark."},
	{"id": "cruise", "name": "CRUISE MISSILE", "at": 10,
		"note": "Launched at a spot you pick on the map. It flies itself in, then you steer it down from above the target with every hostile marked."},
	{"id": "tacnuke", "name": "TACTICAL NUKE", "at": 20,
		"note": "A small warhead on a spot you pick. Nothing within eighty metres lives and nothing there is left standing — you included."},
	{"id": "emp", "name": "EMP STRIKE", "at": 11,
		"note": "Their electronics die: every sentry and drone of theirs is knocked out, their sights go dark and nothing of theirs gets into the air for a minute."},
	{"id": "chopper", "name": "CHOPPER GUNNER", "at": 12,
		"note": "You on the door gun of a helicopter circling low over the town: closer, faster and more exposed than the AC-130."},
	{"id": "armour", "name": "ARMOUR DROP", "at": 14,
		"note": "A tank comes down under parachutes on a spot you pick on the map. Walk up to it and press U: it is yours until it is knocked out."},
	{"id": "jugg", "name": "JUGGERNAUT", "at": 16,
		"note": "Into a suit of heavy armour with a minigun: it takes most of every hit, but you cannot sprint and you move slowly."},
	{"id": "wp", "name": "WHITE PHOSPHORUS", "at": 15,
		"note": "Two points on the map set a line; a hundred metres of it burns for twenty-five seconds and chokes with smoke. It burns anyone in it, yours included."},
	{"id": "stratnuke", "name": "STRATEGIC NUKE", "at": 30,
		"note": "The town, everything in it and the match. Twenty seconds' warning and nowhere to go."},
]
const MAX_STREAKS := 4

## What he carries into the next life, by id. The four the game always had,
## until he changes them.
static var streak_pick: Array = ["uav", "strike", "gunship", "missile"]
const UAV_TIME := 30.0
var streak := 0
var bank := {"uav": 0, "mortar": 0, "strike": 0, "strafe": 0, "gunship": 0, "carpet": 0,
	"missile": 0, "cruise": 0, "tacnuke": 0, "stratnuke": 0, "smoke": 0, "cuav": 0,
	"supply": 0, "vest": 0, "sentry": 0, "emp": 0, "wp": 0, "swarm": 0, "heli": 0, "armour": 0, "chopper": 0, "dogs": 0, "jugg": 0}

## Seconds each side's air is jammed for by the other's COUNTER-UAV: no map
## picture and nothing of theirs called into the air. By team.
static var jammed := {0: 0.0, 1: 0.0}

## Seconds each side's electronics are dead for under the other's EMP: their
## optics are dark (they shoot over iron sights, or none) and their air is
## jammed with it. By team.
static var emp_t := {0: 0.0, 1: 0.0}
const EMP_TIME := 60.0
const JAM_TIME := 45.0

## What a counter-UAV keeps on the ground.
const AIR_STREAKS := ["uav", "strike", "strafe", "gunship", "carpet", "cruise", "swarm", "heli", "armour", "chopper"]

## The cruise missile in the air, if there is one.
var cruise: CruiseMissile = null

## Warheads on their way: [seconds left, where, lethal radius, strategic].
var nukes: Array = []
const TAC_LETHAL := 80.0
const STRAT_LETHAL := 1500.0

## The drone a UAV streak puts up, while it is up.
var uav: UavDrone = null

## The first end of a white phosphorus strip, between its two picks.
var wp_from := Vector3.INF
const WP_MAX := 100.0

## How long the attack helicopter stays over the town.
const HELI_TIME := 55.0

## How far out the ATTACK HELICOPTER is called up from.
const HELI_IN := 1800.0

## The first end of a smoke screen's line, between its two picks.
var _smoke_from := Vector3.INF

## The longest screen one barrage lays.
const SMOKE_MAX := 120.0

## The first end of a carpet's line, while the map waits for the second.
var carpet_from := Vector3.INF

## Where a gun run's line starts, between its two picks.
var strafe_from := Vector3.INF

## Cannon rounds that have landed, for the harness.
var cannon_hits := 0
var uav_t := 0.0
var bombs: Array = []            # [seconds until it lands, where, how big]

## Mortar rounds called down and not yet landed, in the air or waiting their
## turn in the tube.
var rounds: Array = []

## Where the last mortar barrage is being fired from, for the map.
var _battery := Vector3.INF

## Points to spend on the deploy screen, from kills: see `ride_cost`.
var points := 0

# ---------------------------------------------------------- strikes, shared
## The strikes that are drawn on every screen: called here, replayed as a
## picture everywhere else. The rest are either already shared some other
## way -- the attack helicopter is flown by the host, the gunships are the
## caller's own aircraft, the missile goes from a launcher -- or are this
## machine's business: the map picture of a UAV, a suit of armour.
const PICTURED := ["strike_at", "strafe_at", "mortar_at", "carpet_at", "wp_at", "smoke_at",
	"swarm", "tacnuke_at", "stratnuke_at", "cruise_at"]
var _picturing := false
var _pic_caller: Node3D = null
var _pic_yaw := 0.0

## What can only be done by a man standing in the street.
const FOOT_STREAKS := ["jugg", "dogs", "sentry", "vest"]
var _picking := false
var pick_at := Vector3.ZERO

## Seconds from the call to the last of it landing, and one more to see it.
const MARK_SECONDS := {"tacnuke": 14.0, "stratnuke": 22.0, "strike": 30.0,
	"mortar": 20.0, "missile": 50.0}
var _pick_node: Node = null

## One bomb of the stick, one mortar round, or the one big bomb: `big` is
## how much bigger or smaller than a stick bomb it is. It does not care about
## walls and it does not care whose side anyone is on, the man who called it
## included.
var _carpet_n := 0

func _init(w: CqbMatch) -> void:
	fight = w

## A kill by this machine's player: the points, one more in the run, and
## whatever rung of the ladder he carries that reaches.
func earn(head: bool) -> void:
	points += 150 if head else 100
	streak += 1
	var carried: Array = chosen_streaks()
	var top := 1
	for k0 in carried:
		top = maxi(top, int(k0["at"]))
	for k in carried:
		# the ladder comes round again after the top rung of what he carries
		if (streak - 1) % top + 1 == int(k["at"]):
			bank[k["id"]] = int(bank[k["id"]]) + 1
			Sim.report("%d in a row — %s ready, press %d" % [streak, String(k["name"]),
				int(k["key"])], Sim.Ev.GOOD)
			Sfx.play_ui(fight.world, "killmark", -4.0, 0.7)

## Warheads still on their way down, freed with the match: they belong to the
## world, not to it.
func drop_warheads() -> void:
	for nk in nukes:
		if nk.size() > 6 and is_instance_valid(nk[6]):
			(nk[6] as Node).queue_free()

## The carried ones, cheapest first, each with the key that spends it.
static func chosen_streaks() -> Array:
	var out: Array = []
	for k in STREAK_POOL:
		if streak_pick.has(String(k["id"])):
			out.append((k as Dictionary).duplicate())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	for i in out.size():
		out[i]["key"] = 4 + i
	return out

## A low pass down a line letting canisters go every `step` metres: smoke or
## white phosphorus, instead of bombs. The run is a `CarpetRun`, so the map
## has the aircraft coming in and the canisters falling.
func _payload_run(what: String, a: Vector3, b: Vector3, label: String, step: float) -> CarpetRun:
	var nato: bool = ["usa", "uk", "france"].has(Sim.home_faction)
	var r := CarpetRun.new()
	r.arena = fight
	r.payload = what
	r.spec_id = "a10" if nato else "su35"
	r.label = label
	r.speed = 140.0
	r.height = 90.0
	r.spacing = step
	r.longest = maxf(a.distance_to(b), 10.0)
	r.run_in = 2600.0
	r.cluster = false
	r.load_weapon = "gbu32"
	r.min_bombs = 2
	r.max_bombs = 24
	r.from = Vector3(a.x, fight._ground(a.x, a.z), a.z)
	r.to = Vector3(b.x, fight._ground(b.x, b.z), b.z)
	fight.world.add_child(r)
	return r

## What a ride costs on the deploy screen in a ground or combined fight. A
## vehicle or an aircraft was free for the asking, so a combined fight opened
## with everybody in the air; now it is earned, the lighter things first.
static func ride_cost(what: String) -> int:
	if what == "foot" or what == "":
		return 0
	if what.begins_with("veh:"):
		var kd: Dictionary = VehicleSpec.KINDS.get(what.substr(4), {})
		return {"lav": 200, "ifv": 400, "spaag": 400, "mbt": 600}.get(
			String(kd.get("class", "")), 500)
	return 900 if JetSpec.is_rotary(what) else 1200

## Where the player is looking, on the ground or a wall.
func _mark() -> Vector3:
	var eye_cam: Camera3D = fight.player.cam if is_instance_valid(fight.player) and is_instance_valid(fight.player.cam) \
		else fight.get_viewport().get_camera_3d()
	if eye_cam == null:
		return Vector3.INF
	var eye: Vector3 = eye_cam.global_position
	var look: Vector3 = -eye_cam.global_transform.basis.z
	var d: float = Firearm.sight_range(eye, look, 500.0)
	if d >= 499.0:
		return Vector3.INF
	var p: Vector3 = eye + look * d
	return Vector3(p.x, fight._ground(p.x, p.z), p.z)

func support(delta: float) -> void:
	# Whatever falls out of the sky during this match was called by him, and
	# is not meant for his own side.
	# With armour about that stops being true: a shell is a shell, whoever
	# fired it and whoever is standing where it lands.
	Effects.credit = fight.player if (is_instance_valid(fight.player) and not fight.armour) else null
	Effects.spare_team = -1 if fight.armour else 0
	uav_t = maxf(uav_t - delta, 0.0)
	if uav_t <= 0.0 and is_instance_valid(uav):
		uav.queue_free()
		uav = null
	var still: Array = []
	for nk in nukes:
		nk[0] = float(nk[0]) - delta
		var rv: Node3D = nk[6] if nk.size() > 6 else null
		if float(nk[0]) > 0.0:
			still.append(nk)
			if is_instance_valid(rv):
				var pos := _warhead_at(nk)
				var dir: Vector3 = (nk[1] as Vector3) - pos
				rv.global_position = pos
				if dir.length() > 1.0:
					rv.look_at(pos + dir, Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.FORWARD)
		else:
			if is_instance_valid(rv):
				rv.queue_free()
			_nuke(nk[1], float(nk[2]), bool(nk[3]), nk.size() > 7 and bool(nk[7]))
	nukes = still
	for tm in jammed:
		jammed[tm] = maxf(float(jammed[tm]) - delta, 0.0)
	for tm in emp_t:
		emp_t[tm] = maxf(float(emp_t[tm]) - delta, 0.0)
	fight._plan_tick(delta)
	if _picking and fight.world.get("map") != null and is_instance_valid(fight.world.map) \
			and not fight.world.map.pick_cb.is_valid():
		_picking = false
	var on_duty: bool = (is_instance_valid(fight.player) and fight.player.is_alive() and not fight.away) \
		or (not is_instance_valid(fight.player) and caller() != null)
	if on_duty:
		for k in chosen_streaks():
			if int(bank[k["id"]]) > 0 and Sim.tapped(StringName("weapon_%d" % int(k["key"]))):
				if AIR_STREAKS.has(String(k["id"])) and float(jammed[0]) > 0.0:
					Sim.report("jammed — nothing goes up for another %d seconds" % int(float(jammed[0])),
						Sim.Ev.BAD)
					continue
				if call_in(String(k["id"])):
					bank[k["id"]] = int(bank[k["id"]]) - 1
					_share_streak(String(k["id"]))
	var keep: Array = []
	for b in bombs:
		b[0] = float(b[0]) - delta
		if float(b[0]) > 0.0:
			keep.append(b)
			continue
		bomb(b[1], float(b[2]) if b.size() > 2 else 1.0, false, "strike")
	bombs = keep

## What is on its way in, for the map: everything this side has called down
## that has not arrived yet, as dictionaries the map knows how to draw.
##   kind   "bombs", "nuke", "plane", "missile", "drone", "mark"
##   at     where it is coming down, or where it is now if it flies
##   eta    seconds until it lands, where that is known
##   r      how far its blast reaches, in metres
##   from / to   a line it is flying along
##   head   which way it is pointing, flat
##   label  what to call it
func inbound() -> Array:
	var out: Array = []
	# Bombs and shells that have been called and not landed: grouped by where
	# they fall, so an airstrike is one mark with a countdown and not seven.
	var groups: Array = []
	for b in bombs:
		var at: Vector3 = b[1]
		var big: float = float(b[2]) if b.size() > 2 else 1.0
		var put := false
		for g in groups:
			if Vector2(at.x - (g["at"] as Vector3).x, at.z - (g["at"] as Vector3).z).length() < 70.0:
				(g["pts"] as Array).append(at)
				g["eta"] = minf(float(g["eta"]), float(b[0]))
				g["last"] = maxf(float(g["last"]), float(b[0]))
				g["r"] = maxf(float(g["r"]), 9.0 * big)
				put = true
				break
		if not put:
			groups.append({"kind": "bombs", "at": at, "pts": [at], "eta": float(b[0]),
				"last": float(b[0]), "r": 9.0 * big})
	# The mortar rounds' marks, the same way, and the rounds themselves in the
	# air.
	var live: Array = []
	for mr in rounds:
		if not is_instance_valid(mr):
			continue
		live.append(mr)
		var m2: MortarRound = mr
		var put2 := false
		for g in groups:
			if Vector2(m2.to.x - (g["at"] as Vector3).x, m2.to.z - (g["at"] as Vector3).z).length() < 70.0:
				(g["pts"] as Array).append(m2.to)
				g["eta"] = minf(float(g["eta"]), m2.eta())
				put2 = true
				break
		if not put2:
			groups.append({"kind": "bombs", "at": m2.to, "pts": [m2.to], "eta": m2.eta(),
				"last": m2.eta(), "r": 9.0 * 0.65})
		if m2.in_air():
			out.append({"kind": "shell", "at": m2.global_position, "head": m2.vel})
	rounds = live
	if not live.is_empty() and _battery != Vector3.INF:
		out.append({"kind": "gun", "at": _battery, "label": "MORTARS"})
	for g in groups:
		var n: int = (g["pts"] as Array).size()
		g["label"] = "BOMB" if n == 1 else ("%d ROUNDS" % n)
		out.append(g)
	for nk in nukes:
		out.append({"kind": "nuke", "at": nk[1], "eta": float(nk[0]), "r": float(nk[2]),
			"label": "STRATEGIC NUKE" if bool(nk[3]) else "TACTICAL NUKE"})
		# and the warhead itself, on its way down the track to the mark
		if nk.size() > 5:
			out.append({"kind": "missile", "at": _warhead_at(nk),
				"head": (nk[1] as Vector3) - (nk[4] as Vector3),
				"from": nk[4], "to": nk[1], "label": "WARHEAD", "eta": float(nk[0])})
	# armour he had dropped, where it is now
	for v in fight.get_tree().get_nodes_in_group("vehicles"):
		var tv := v as Tank
		if tv != null and tv.alive and tv.team == 0 and tv.has_meta("dropped"):
			out.append({"kind": "mark", "at": tv.global_position, "r": 6.0,
				"label": "YOUR %s" % tv.display_name().to_upper()})
	for n2 in fight.world.get_children():
		if n2 is CarpetRun and is_instance_valid(n2):
			var cr := n2 as CarpetRun
			out.append({"kind": "plane", "at": cr.global_position, "head": cr._dir,
				"from": cr.from, "to": cr.to, "label": cr.label,
				"eta": cr.until_first(), "gone": cr.until_gone()})
		elif n2 is GunRun and is_instance_valid(n2):
			var gr2 := n2 as GunRun
			out.append({"kind": "plane", "at": gr2.lead_at(), "head": gr2._dir,
				"from": gr2.from, "to": gr2.to, "label": "A-10 GUN RUN",
				"eta": gr2.until_fire()})
		elif n2 is CarpetBomb and is_instance_valid(n2):
			out.append({"kind": "falling", "at": (n2 as Node3D).global_position})
		# what this side has put on the ground and in the air besides
		elif n2 is SmokeScreen and is_instance_valid(n2):
			var ss := n2 as SmokeScreen
			out.append({"kind": "area", "at": ss.from.lerp(ss.to, 0.5), "from": ss.from,
				"to": ss.to, "label": "SMOKE", "tint": Color(0.75, 0.78, 0.8)})
		elif n2 is NapalmStrike and is_instance_valid(n2):
			var ns2 := n2 as NapalmStrike
			out.append({"kind": "area", "at": ns2.from.lerp(ns2.to, 0.5), "from": ns2.from,
				"to": ns2.to, "label": "BURNING", "tint": Color(1.0, 0.45, 0.15)})
		elif n2 is SupplyCrate and is_instance_valid(n2):
			var sc2 := n2 as SupplyCrate
			var falling: bool = not sc2.is_in_group("pickups")
			out.append({"kind": "mark", "at": sc2.target, "r": 4.0,
				"label": ("SUPPLY" if sc2.kind == "supply" else "VESTS") + (
					"  %ds" % int(ceil((sc2.global_position.y - sc2.target.y) / SupplyCrate.FALL_SPEED))
					if falling else "")})
		elif n2 is VehicleDrop and is_instance_valid(n2) and is_instance_valid((n2 as VehicleDrop).vehicle):
			var vt: Tank = (n2 as VehicleDrop).vehicle
			out.append({"kind": "mark", "at": vt.global_position, "r": 6.0,
				"label": "%s  %ds" % [vt.display_name().to_upper(),
					int(ceil((vt.global_position.y - (n2 as VehicleDrop)._ground) / VehicleDrop.SINK))]})
		elif n2 is SentryTurret and is_instance_valid(n2) and (n2 as SentryTurret).team == 0 \
				and (n2 as SentryTurret).alive:
			out.append({"kind": "gun", "at": (n2 as Node3D).global_position,
				"label": "SENTRY %d" % (n2 as SentryTurret).rounds})
		elif n2 is Switchblade and is_instance_valid(n2) and (n2 as Switchblade).team == 0:
			var swd := n2 as Switchblade
			var st_d: Dictionary = {"kind": "drone", "at": swd.global_position, "head": swd.vel,
				"label": "SWITCHBLADE"}
			if is_instance_valid(swd._target):
				st_d["to"] = swd._target.global_position
			out.append(st_d)
		elif n2 is AttackDog and is_instance_valid(n2) and (n2 as AttackDog).alive \
				and (n2 as AttackDog).team == 0:
			out.append({"kind": "unit", "at": (n2 as Node3D).global_position, "label": "K9"})
		elif n2 is AIHeli and is_instance_valid(n2) and (n2 as AIHeli).arena == fight:
			out.append({"kind": "plane", "at": (n2 as Node3D).global_position,
				"head": (n2 as AIHeli).linear_velocity, "label": "GUNSHIP",
				"eta": maxf((n2 as AIHeli).patrol_t, 0.0)})
	if is_instance_valid(cruise):
		var v: Vector3 = cruise.vel
		out.append({"kind": "missile", "at": cruise.global_position, "head": v,
			"to": cruise.target, "label": "CRUISE MISSILE",
			"eta": cruise.global_position.distance_to(cruise.target) / maxf(v.length(), 1.0)})
	if is_instance_valid(uav):
		out.append({"kind": "drone", "at": uav.global_position, "head": uav.linear_velocity,
			"r": UavDrone.RADIUS, "mid": uav._mid, "label": "UAV %ds" % int(uav_t)})
	var ship: Variant = fight.world.get("called_gunship")
	if ship != null and is_instance_valid(ship):
		var sh := ship as Node3D
		out.append({"kind": "plane", "at": sh.global_position,
			"head": (sh as Aircraft).linear_velocity, "label": "GUNSHIP"})
	var tel: Variant = fight.world.get("cqb_tel")
	if tel != null and is_instance_valid(tel) and float(fight.world.get("cqb_tel_t")) > 0.0:
		var t := tel as Tank
		if t.map_target != Vector3.INF:
			out.append({"kind": "mark", "at": t.map_target, "r": 25.0,
				"label": "FIRE MISSION", "eta": -1.0})
		# where it is firing from, so the rounds are seen coming from somewhere
		out.append({"kind": "gun", "at": t.global_position, "label": t.display_name().to_upper()})
		for m in fight.get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m) and (m as Node).get("shooter") == t:
				out.append({"kind": "missile", "at": (m as Node3D).global_position,
					"head": (m as Node).get("vel"), "to": t.map_target, "label": ""})
		# A rocket launcher's rounds are shells, not missiles: the M270 lays a
		# ripple of them, and none of it was on the map until it had landed.
		for sh2 in fight.get_tree().get_nodes_in_group("shells"):
			if is_instance_valid(sh2) and (sh2 as Node).get("shooter") == t:
				out.append({"kind": "shell", "at": (sh2 as Node3D).global_position,
					"head": (sh2 as Node).get("vel")})
	return out

## Who called it in: the man on foot, or whatever he is crewing -- a tank in a
## ground fight, an aeroplane over a combined one. Streaks were only ever
## called by the man on foot, so in either of those, where you spend most of
## the match, the keys did nothing and the kills earned nothing.
func caller() -> Node3D:
	if _picturing and is_instance_valid(_pic_caller):
		return _pic_caller
	if is_instance_valid(fight.player):
		return fight.player
	if fight.world != null:
		var t: Variant = fight.world.get("tank")
		if t != null and is_instance_valid(t) and bool(t.get("alive")):
			return t
		var p: Variant = fight.world.get("player")
		if p != null and is_instance_valid(p) and not bool(fight.world.get("on_foot")) \
				and bool(p.get("active")) and p.is_alive():
			return p
	return null

func _who_yaw() -> float:
	if _picturing:
		return _pic_yaw
	var w := caller()
	if w == null:
		return 0.0
	if w == fight.player:
		return fight.player.yaw
	return w.global_rotation.y

## The ATTACK HELICOPTER, for `team` (this machine's frame), in from `back`
## of the town. Called here for the player, or by the host for a player on
## another machine.
func spawn_streak_heli(team: int, back: Vector3) -> AIHeli:
	var nato_h: bool = ["usa", "uk", "france"].has(Sim.home_faction) == (team == 0)
	var h := AIHeli.new()
	h.setup("ah64" if nato_h else "mi28")
	h.team = team
	h.name = "Gunship"
	h.arena = fight
	h.patrol_t = HELI_TIME
	var c3 := Vector3(fight.centre.x, fight._ground(fight.centre.x, fight.centre.y), fight.centre.y)
	h.home = c3
	h.station_alt = 140.0
	fight.world.add_child(h)
	# In from behind him, from far enough out to be seen and heard coming. Put
	# down six hundred metres off it was simply there; it now flies in at a
	# transit speed and its time on station starts when it arrives, so the trip
	# costs none of it.
	var at: Vector3 = c3 + back * HELI_IN
	at.y = fight._ground(at.x, at.z) + AIHeli.NAP_AGL
	h.global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP), at)
	h.linear_velocity = -back * 50.0
	h.inbound = true
	return h

func _share_streak(which: String) -> void:
	if not PICTURED.has(which) or Sim.net == null or not Sim.net.active:
		return
	var w := caller()
	var x := {"cpos": w.global_position if w != null else Vector3(fight.centre.x, 0.0, fight.centre.y),
		"cyaw": _who_yaw(), "strafe": strafe_from, "carpet": carpet_from,
		"wp": wp_from, "smoke": _smoke_from}
	Sim.net.launches.share_streak(which, pick_at, x)

## Somebody on another machine called a strike: the same strike, run here as
## a picture -- the aircraft, the bombs, the cloud -- with nothing in it that
## hurts anybody. The damage is dealt on the caller's machine, and reaches
## everyone through the hits it reports, the same as his rifle's.
func call_picture(which: String, at: Vector3, x: Dictionary, who: String, friendly: bool) -> void:
	if not PICTURED.has(which):
		return
	pick_at = at
	strafe_from = x.get("strafe", Vector3.INF)
	carpet_from = x.get("carpet", Vector3.INF)
	wp_from = x.get("wp", Vector3.INF)
	_smoke_from = x.get("smoke", Vector3.INF)
	_pic_caller = Node3D.new()
	fight.world.add_child(_pic_caller)
	_pic_caller.global_position = x.get("cpos", at)
	_pic_yaw = float(x.get("cyaw", 0.0))
	var made: Array = []
	var catch_it := func(n: Node) -> void: made.append(n)
	fight.world.child_entered_tree.connect(catch_it)
	_picturing = true
	Sim.mute_reports = true
	var keep_node: Node = _pick_node
	call_in(which)
	Sim.mute_reports = false
	_picturing = false
	_pick_node = keep_node
	fight.world.child_entered_tree.disconnect(catch_it)
	for n in made:
		if not is_instance_valid(n):
			continue
		if "picture" in n:
			n.set("picture", true)
		elif n is Missile:
			(n as Missile).harmless = true
	_pic_caller.queue_free()
	_pic_caller = null
	var nm := String(which).trim_suffix("_at").to_upper()
	for k in STREAK_POOL:
		if String(k["id"]) == which.trim_suffix("_at"):
			nm = String(k["name"])
	Sim.report("%s called in: %s" % [who, nm], Sim.Ev.GOOD if friendly else Sim.Ev.BAD)

func call_in(id: String) -> bool:
	if caller() == null:
		return false
	if not is_instance_valid(fight.player) and FOOT_STREAKS.has(id):
		Sim.report("%s — only on foot" % id.to_upper(), Sim.Ev.BAD)
		return false
	match id:
		"armour":
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				fight.world.map.pick("ARMOUR DROP", func(p: Vector3): picked("armour", p))
			return false
		"armour_at":
			if not fight.world.has_method("_spawn_tank"):
				return false
			var kind := "m1a2"
			for k in VehicleSpec.KINDS:
				var kd: Dictionary = VehicleSpec.KINDS[k]
				if String(kd.get("class", "")) == "mbt" and String(kd.get("faction", "")) == Sim.home_faction:
					kind = k
					break
			var at: Vector3 = Vector3(pick_at.x, fight._ground(pick_at.x, pick_at.z), pick_at.z)
			var tk: Tank = fight.world._spawn_tank(at, _who_yaw(), 0, kind)
			if not is_instance_valid(tk):
				return false
			var vd := VehicleDrop.new()
			vd.vehicle = tk
			fight.world.add_child(vd)
			_pick_node = vd
			Sim.report("armour inbound — a %s under canopies, about %d seconds" % [
				tk.display_name(), int(VehicleDrop.FROM / VehicleDrop.SINK)], Sim.Ev.GOOD)
			return true
		"heli":
			var back := Vector3(sin(_who_yaw()), 0.0, cos(_who_yaw()))
			if NetLink.mirroring():
				# The host flies it, on our side, so everyone sees the same
				# helicopter: one flown here would be on this screen only.
				Sim.net.launches.request_heli(back)
			else:
				spawn_streak_heli(0, back)
			Sim.report("gunship inbound from behind you — over the town in about %d seconds" % int(
				(HELI_IN - AIHeli.ON_STATION) / 55.0 + 2.0), Sim.Ev.GOOD)
			return true
		"jugg":
			if not is_instance_valid(fight.player) or fight.player.juggernaut:
				return false
			fight.player.suit_up()
			Sim.report("juggernaut — %d of armour and a minigun; no sprinting" % int(Walker.JUGG_ARMOUR),
				Sim.Ev.GOOD)
			return true
		"dogs":
			var dc: Vector3 = caller().global_position
			for i in 3:
				var dg := AttackDog.new()
				dg.team = 0
				dg.arena = fight
				dg.owner_node = fight.player
				dg.slot = i
				fight.world.add_child(dg)
				var off := Vector3(cos(TAU * i / 3.0) * 1.2, 0.0, sin(TAU * i / 3.0) * 1.2)
				dg.global_position = Vector3(dc.x + off.x, fight._ground(dc.x + off.x, dc.z + off.z), dc.z + off.z)
			Sim.report("dogs loose — three of them, after the nearest of theirs", Sim.Ev.GOOD)
			return true
		"swarm":
			# A transport over him, and four off its ramp as it passes.
			var c: Vector3 = caller().global_position
			var fwd_s := Vector3(-sin(_who_yaw()), 0.0, -cos(_who_yaw()))
			var run := CarpetRun.new()
			run.arena = fight
			run.payload = "drones"
			run.drone_centre = c
			run.spec_id = "c130"
			run.label = "SWITCHBLADES"
			run.speed = 120.0
			run.height = 320.0
			run.spacing = 25.0
			run.longest = 75.0
			run.run_in = 3000.0
			run.cluster = false
			run.min_bombs = 4
			run.max_bombs = 4
			var sa: Vector3 = c - fwd_s * 40.0
			var sb2: Vector3 = c + fwd_s * 35.0
			run.from = Vector3(sa.x, fight._ground(sa.x, sa.z), sa.z)
			run.to = Vector3(sb2.x, fight._ground(sb2.x, sb2.z), sb2.z)
			fight.world.add_child(run)
			Sim.report("switchblades inbound — a transport over you in about %d seconds, four off the ramp" % int(run.eta),
				Sim.Ev.GOOD)
			return true
		"wp":
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				wp_from = Vector3.INF
				fight.world.map.pick("WHITE PHOSPHORUS — click where the strip STARTS", func(p: Vector3):
					wp_from = p
					fight.world.map.pick("WHITE PHOSPHORUS — click where it ENDS",
						func(q: Vector3): picked("wp", q)))
			return false
		"wp_at":
			var a: Vector3 = wp_from if wp_from != Vector3.INF else pick_at
			var run: Vector3 = pick_at - a
			run.y = 0.0
			if run.length() < 3.0:
				# one click: across his line to it, sixty metres
				var look2 := Vector3(pick_at.x - caller().global_position.x, 0.0,
					pick_at.z - caller().global_position.z).normalized()
				var across2: Vector3 = look2.cross(Vector3.UP).normalized()
				a = pick_at - across2 * 30.0
				run = across2 * 60.0
			var bw: Vector3 = a + run.normalized() * minf(run.length(), WP_MAX)
			var wr := _payload_run("wp", a, bw, "WHITE PHOSPHORUS", NapalmStrike.STEP)
			_pick_node = wr
			wp_from = Vector3.INF
			Sim.report("white phosphorus run inbound — about %d seconds, keep out of the line" % int(wr.eta),
				Sim.Ev.GOOD)
			return true
		"emp":
			emp_t[1] = EMP_TIME
			jammed[1] = maxf(float(jammed[1]), EMP_TIME)
			var killed := 0
			# everything of theirs that runs on electricity and is out there
			for grp in ["sentries", "drones"]:
				for n in fight.get_tree().get_nodes_in_group(grp):
					if not is_instance_valid(n) or int(n.get("team")) == 0:
						continue
					if n.has_method("take_hit"):
						n.take_hit(100000.0, fight.player)
					else:
						(n as Node).queue_free()
					killed += 1
			Effects.emp_flash(fight.world, caller().global_position)
			Sim.report("EMP — their sights and electronics are dead for a minute%s" % (
				"; %d of their systems knocked out" % killed if killed > 0 else ""), Sim.Ev.GOOD)
			return true
		"sentry":
			if not is_instance_valid(fight.player) or not fight.player.on_floor:
				Sim.report("set it down on solid ground", Sim.Ev.BAD)
				return false
			var fwd := Vector3(-sin(_who_yaw()), 0.0, -cos(_who_yaw()))
			var at: Vector3 = caller().global_position + fwd * 1.4
			at.y = fight._ground(at.x, at.z)
			if Obstacles.blocks(at + Vector3(0, 0.5, 0), 0.4) >= 0:
				Sim.report("no room to set it down here", Sim.Ev.BAD)
				return false
			var st := SentryTurret.new()
			st.team = 0
			st.arena = fight
			st.owner_node = fight.player
			st.facing = _who_yaw()
			fight.world.add_child(st)
			st.global_position = at
			Sim.report("sentry up — it watches %d degrees either side of where you faced" % int(rad_to_deg(SentryTurret.ARC)),
				Sim.Ev.GOOD)
			return true
		"cuav":
			jammed[1] = JAM_TIME
			# whatever of theirs is already up comes down
			for n in fight.get_tree().get_nodes_in_group("hittable"):
				if n is UavDrone and int(n.get("team")) == 1:
					(n as Node).queue_free()
			Sim.report("counter-UAV up — their map is noise and their air is grounded for %d seconds"
				% int(JAM_TIME), Sim.Ev.GOOD)
			return true
		"smoke":
			# two picks, like the carpet: where the screen starts and ends
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				_smoke_from = Vector3.INF
				fight.world.map.pick("SMOKE — click where the screen STARTS", func(p: Vector3):
					_smoke_from = p
					fight.world.map.pick("SMOKE — click where it ENDS",
						func(q: Vector3): picked("smoke", q)))
			return false
		"supply", "vest":
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				var title: String = {"supply": "SUPPLY DROP", "vest": "BALLISTIC VEST DROP"}[id]
				fight.world.map.pick(title, func(p: Vector3): picked(id, p))
			return false
		"smoke_at":
			# Laid by an aircraft down the line he drew: a canister every few
			# metres, each a bank of smoke where it lands. A single click lays
			# it across his line to the mark, sixty metres wide.
			var sa: Vector3 = _smoke_from
			var sb: Vector3 = pick_at
			if sa == Vector3.INF or sa.distance_to(sb) < 3.0:
				var look := Vector3(pick_at.x - caller().global_position.x, 0.0,
					pick_at.z - caller().global_position.z)
				look = look.normalized() if look.length() > 2.0 else Vector3(-sin(_who_yaw()), 0.0, -cos(_who_yaw()))
				var across: Vector3 = look.cross(Vector3.UP).normalized()
				sa = pick_at - across * 30.0
				sb = pick_at + across * 30.0
			var run_s: Vector3 = sb - sa
			run_s.y = 0.0
			sb = sa + run_s.normalized() * minf(run_s.length(), SMOKE_MAX)
			var sr := _payload_run("smoke", sa, sb, "SMOKE", SmokeScreen.SPACING)
			_pick_node = sr
			_smoke_from = Vector3.INF
			Sim.report("smoke run inbound — canisters down your line in about %d seconds" % int(sr.eta),
				Sim.Ev.GOOD)
			return true
		"supply_at", "vest_at":
			var cr := SupplyCrate.new()
			cr.kind = "supply" if id == "supply_at" else "vest"
			cr.team = 0
			cr.target = Vector3(pick_at.x, fight._ground(pick_at.x, pick_at.z), pick_at.z)
			fight.world.add_child(cr)
			_pick_node = cr
			Sim.report("%s inbound — under a parachute, about %d seconds" % [
				"supply drop" if cr.kind == "supply" else "vest drop",
				int(SupplyCrate.FALL_FROM / SupplyCrate.FALL_SPEED)], Sim.Ev.GOOD)
			return true
		"uav":
			uav_t = UAV_TIME
			# A drone, in the sky, where it can be seen and shot at: the map
			# shows what it sees for as long as it is still flying.
			if not is_instance_valid(uav):
				uav = UavDrone.new()
				uav.arena = fight
				uav.team = 0
				uav.name = "UAV"
				fight.world.add_child(uav)
				uav.station(Vector3(fight.centre.x, fight._ground(fight.centre.x, fight.centre.y), fight.centre.y))
			Sim.report("UAV overhead — hostiles on the map for %d seconds, unless they shoot it down" % int(UAV_TIME), Sim.Ev.GOOD)
			return true
		"tacnuke", "stratnuke":
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				fight.world.map.pick("TACTICAL NUKE" if id == "tacnuke" else "STRATEGIC NUKE",
					func(p: Vector3): picked(id, p))
			return false
		"tacnuke_at":
			var at3: Vector3 = pick_at
			add_nuke(12.0, Vector3(at3.x, fight._ground(at3.x, at3.z), at3.z), TAC_LETHAL, false)
			Sim.report("TACTICAL NUKE inbound — twelve seconds, get eighty metres clear of the mark", Sim.Ev.BAD)
			# No warm-up copy of the cloud. One was put four metres in front of
			# the camera here to have its shaders built early, and the raymarch
			# filling the screen was itself a 2.7 second frame; the engine
			# builds them without stopping now (`--stalltest=tacnuke`).
			Sfx.play_at(fight.world, "roar", at3 + Vector3(0, 900, 0), 9.0, 0.7, 9000.0)
			return true
		"stratnuke_at":
			var at4: Vector3 = pick_at
			add_nuke(20.0, Vector3(at4.x, fight._ground(at4.x, at4.z), at4.z), STRAT_LETHAL, true)
			Sim.report("STRATEGIC NUKE inbound — twenty seconds. It has been an honour.", Sim.Ev.BAD)
			Sfx.play_at(fight.world, "roar", at4 + Vector3(0, 2000, 0), 10.0, 0.55, 12000.0)
			return true
		"strike":
			# On the map, not down the sights: what you want hit is usually
			# round a corner, which is why you are calling for it.
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				fight.world.map.pick("AIRSTRIKE", func(p: Vector3): picked("strike", p))
				return false
			return false
		"strike_at":
			var at: Vector3 = pick_at
			# A pair of strike jets down the line from him to the mark, low and
			# fast, with a stick of bombs walked through it. It was seven bombs
			# on a timer and the sound of a jet: nothing came over, and nothing
			# was on the map until the bombs were.
			var run := Vector3(at.x - caller().global_position.x, 0.0, at.z - caller().global_position.z)
			run = run.normalized() if run.length() > 1.0 else Vector3(-sin(_who_yaw()), 0.0, -cos(_who_yaw()))
			var nato: bool = ["usa", "uk", "france"].has(Sim.home_faction)
			var sr := CarpetRun.new()
			sr.arena = fight
			sr.spec_id = "a10" if nato else "su35"
			sr.label = "AIRSTRIKE"
			sr.speed = 210.0
			sr.height = 320.0
			sr.spacing = 13.0
			sr.longest = 100.0
			sr.run_in = 2600.0
			sr.cluster = false
			sr.load_weapon = "gbu32"
			sr.min_bombs = 8
			sr.max_bombs = 8
			sr.wing = Vector3(38.0, 6.0, 34.0)
			var a0: Vector3 = at - run * 45.0
			var a1: Vector3 = at + run * 55.0
			sr.from = Vector3(a0.x, fight._ground(a0.x, a0.z), a0.z)
			sr.to = Vector3(a1.x, fight._ground(a1.x, a1.z), a1.z)
			fight.world.add_child(sr)
			_pick_node = sr
			Sim.report("airstrike inbound — a pair of %s down your line, bombs in about %d seconds, get down" % [
				"A-10s" if nato else "Su-35s", int(sr.eta)], Sim.Ev.GOOD)
			return true
		"mortar":
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				fight.world.map.pick("MORTAR BARRAGE", func(p: Vector3): picked(id, p))
			return false
		"strafe":
			# two picks, like the carpet: where the guns open, then where they stop
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				strafe_from = Vector3.INF
				fight.world.map.pick("A-10 GUN RUN — click where the strafe STARTS", func(p: Vector3):
					strafe_from = p
					fight.world.map.pick("A-10 GUN RUN — click where it ENDS",
						func(q: Vector3): picked("strafe", q)))
			return false
		"strafe_at":
			if strafe_from == Vector3.INF:
				return false
			var gr := GunRun.new()
			gr.arena = fight
			gr.from = Vector3(strafe_from.x, fight._ground(strafe_from.x, strafe_from.z), strafe_from.z)
			gr.to = Vector3(pick_at.x, fight._ground(pick_at.x, pick_at.z), pick_at.z)
			fight.world.add_child(gr)
			_pick_node = gr
			strafe_from = Vector3.INF
			Sim.report("A-10s inbound — a gun run down your line in about %d seconds" % int(gr.eta),
				Sim.Ev.GOOD)
			return true
		"mortar_at":
			# Ten rounds walked over the spot from a battery a kilometre and a
			# bit back on his side of it, each in the air on its own arc.
			var back := Vector3(caller().global_position.x - pick_at.x, 0.0,
				caller().global_position.z - pick_at.z)
			back = back.normalized() if back.length() > 5.0 else Vector3(sin(_who_yaw()), 0.0, cos(_who_yaw()))
			var bat: Vector3 = pick_at + back * 1300.0 + back.cross(Vector3.UP) * fight._rng.randf_range(-250.0, 250.0)
			_battery = Vector3(bat.x, fight._ground(bat.x, bat.z) + 1.0, bat.z)
			for i in 10:
				var off := Vector3(fight._rng.randf_range(-20, 20), 0, fight._rng.randf_range(-20, 20))
				var p: Vector3 = pick_at + off
				var mr := MortarRound.new()
				mr.arena = fight
				mr.from = _battery + Vector3(fight._rng.randf_range(-6, 6), 0.0, fight._rng.randf_range(-6, 6))
				mr.to = MortarRound.lands_at(p.x, p.z)
				# the battery's are 120 mm: heavier on a building than a 60
				mr.blow = 1.6
				mr.blow_r = 8.0
				mr.flight = 12.0 + fight._rng.randf_range(-0.4, 0.4)
				mr.delay = i * 0.7 + fight._rng.randf_range(0.0, 0.3)
				fight.world.add_child(mr)
				rounds.append(mr)
			Sim.report("mortars firing — ten rounds, the first lands in twelve seconds", Sim.Ev.GOOD)
			return true
		"carpet":
			# two picks: where the carpet starts, then where it ends
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				carpet_from = Vector3.INF
				fight.world.map.pick("B-2 — click where the carpet STARTS", func(p: Vector3):
					carpet_from = p
					fight.world.map.pick("B-2 — click where the carpet ENDS",
						func(q: Vector3): picked("carpet", q)))
			return false
		"carpet_at":
			if carpet_from == Vector3.INF:
				return false
			var run := CarpetRun.new()
			run.arena = fight
			run.from = carpet_from
			run.to = pick_at
			fight.world.add_child(run)
			_pick_node = run
			carpet_from = Vector3.INF
			Sim.report("B-2 inbound — a carpet of %d along your line in about %d seconds" % [
				run.bombs, int(run.eta)], Sim.Ev.GOOD)
			return true
		"gunship":
			if fight.world.has_method("cqb_gunship") and fight.world.cqb_gunship(Vector3(fight.centre.x,
					fight._ground(fight.centre.x, fight.centre.y), fight.centre.y)):
				return true
			return false
		"chopper":
			if fight.world.has_method("cqb_gunship") and fight.world.cqb_gunship(Vector3(fight.centre.x,
					fight._ground(fight.centre.x, fight.centre.y), fight.centre.y), "chopper"):
				return true
			return false
		"missile":
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				fight.world.map.pick("FIRE MISSION", func(p: Vector3): picked("missile", p))
			return false
		"missile_at":
			return fight.world.has_method("cqb_fire_mission") and fight.world.cqb_fire_mission(pick_at)
		"cruise":
			if is_instance_valid(cruise):
				Sim.report("one cruise missile at a time", Sim.Ev.BAD)
				return false
			if fight.world.get("map") != null and is_instance_valid(fight.world.map) and not _picking:
				_picking = true
				fight.world.map.pick("CRUISE MISSILE", func(p: Vector3): picked("cruise", p))
			return false
		"cruise_at":
			if is_instance_valid(cruise):
				return false
			cruise = CruiseMissile.new()
			cruise.arena = fight
			cruise.target = Vector3(pick_at.x, fight._ground(pick_at.x, pick_at.z), pick_at.z)
			# in over his own shoulder, so it arrives going the way he is facing
			var back := Vector3(caller().global_position.x - pick_at.x, 0.0,
				caller().global_position.z - pick_at.z)
			cruise.from_dir = back.normalized() if back.length() > 5.0 \
				else Vector3(sin(_who_yaw()), 0.0, cos(_who_yaw()))
			fight.world.add_child(cruise)
			_pick_node = cruise
			Sim.report("cruise missile launched — it is yours in about %d seconds" % int(cruise.eta),
				Sim.Ev.GOOD)
			return true
	return false

## The map came back with a place. Spend the streak on it, if it is still
## there to spend.
func picked(id: String, at: Vector3) -> void:
	_picking = false
	if int(bank.get(id, 0)) <= 0 or caller() == null:
		return
	pick_at = at
	_pick_node = null
	if call_in(id + "_at"):
		bank[id] = int(bank[id]) - 1
		_share_streak(id + "_at")
		# tell the map how long its mark is worth keeping: until the thing
		# itself has gone, or for as long as the last of it takes to land
		if fight.world.get("map") != null and is_instance_valid(fight.world.map):
			if is_instance_valid(_pick_node):
				fight.world.map.pick_life = _pick_node
			elif MARK_SECONDS.has(id):
				fight.world.map.pick_life = float(MARK_SECONDS[id])

## The drone went down: the picture goes with it.
func uav_lost() -> void:
	uav_t = 0.0
	uav = null
	Sim.report("UAV shot down — the map is dark again", Sim.Ev.BAD)

## A warhead going off at `at`. Everything that can be hurt inside `lethal`
## is, whoever's side it is on and the man who called it included; every
## building and everything standing in the street inside it comes down. The
## strategic one ends the match as well: there is nobody left to play it.
## A nuclear call is not just a countdown: there is a warhead, and it comes in
## from somewhere. It used to be a timer and a ring on the map -- nothing on the
## chart and nothing in the sky until the flash. Each one now has a track, from
## well out over the caller's shoulder down to the mark, flown so it arrives on
## the timer: a short range ballistic round for the tactical, a re-entry vehicle
## from much further for the strategic.
##   [eta, at, lethal, strategic, from (with its height), total, the visible body]
func add_nuke(eta: float, at: Vector3, lethal: float, strategic: bool) -> void:
	var reach: float = 120000.0 if strategic else 24000.0
	var top: float = 70000.0 if strategic else 20000.0
	var back := Vector3.ZERO
	if is_instance_valid(fight.player):
		back = fight.player.global_position - at
	back.y = 0.0
	if back.length() < 50.0:
		var a := randf() * TAU
		back = Vector3(cos(a), 0.0, sin(a))
	var from: Vector3 = at + back.normalized() * reach + Vector3(0, top, 0)
	var rv := _warhead_body(strategic)
	fight.world.add_child(rv)
	rv.global_position = from
	nukes.append([eta, at, lethal, strategic, from, eta, rv, _picturing])

## Where a warhead is on its track now: straight down the line, so it is where
## the map says and arrives when the countdown says.
func _warhead_at(nk: Array) -> Vector3:
	var total: float = maxf(float(nk[5]), 0.01)
	var f: float = clampf(1.0 - float(nk[0]) / total, 0.0, 1.0)
	return (nk[4] as Vector3).lerp(nk[1] as Vector3, f)

## A hot re-entry body with a trail: seen as a streak coming down, and the
## glow is what you would actually see of one.
func _warhead_body(strategic: bool) -> Node3D:
	var n := Node3D.new()
	n.name = "Warhead"
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5 if strategic else 0.4
	cone.height = 2.2 if strategic else 1.8
	cone.radial_segments = 10
	mi.mesh = cone
	mi.rotation_degrees = Vector3(-90, 0, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.15, 0.12)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.25)
	m.emission_energy_multiplier = 6.0
	mi.material_override = m
	n.add_child(mi)
	var trail := Effects.trail_particles(Color(1.0, 0.75, 0.45), 6.0 if strategic else 4.0, 60)
	trail.emitting = true
	n.add_child(trail)
	return n

func _nuke(at: Vector3, lethal: float, strategic: bool, picture := false) -> void:
	var scn: Variant = fight.world.get("scenery")
	var flat := lethal * 1.2
	var _p0 := Sim.prof_at()
	if scn != null and is_instance_valid(scn) and scn.has_method("damage_area"):
		scn.damage_area(at, flat)
	else:
		Obstacles.kill_near(at, flat)
	Sim.prof_end(&"nuke.flatten", _p0)
	var _p1 := Sim.prof_at()
	for t in TownSet.live:
		if is_instance_valid(t):
			(t as TownSet).flatten(at, flat)
	Sim.prof_end(&"nuke.town", _p1)
	var _p2 := Sim.prof_at()
	Effects.mute_blast = true
	Effects.nuke(fight.world, at, lethal)
	Effects.mute_blast = false
	Sim.prof_end(&"nuke.fx", _p2)
	if picture:
		return
	var _p3 := Sim.prof_at()
	var seen := {}
	var hurt: Array = fight.soldiers.duplicate()
	hurt.append_array(fight.get_tree().get_nodes_in_group("hittable"))
	if is_instance_valid(fight.player) and not fight.away:
		hurt.append(fight.player)
	var credit: Node = fight.player if is_instance_valid(fight.player) else null
	KillFeed.cause = "nuke"
	for n in hurt:
		if not is_instance_valid(n) or not (n is Node3D) or seen.has(n) \
				or not n.has_method("take_hit"):
			continue
		seen[n] = true
		var d: float = (n as Node3D).global_position.distance_to(at)
		if d < lethal:
			n.take_hit(4000.0 * clampf(1.0 - d / lethal, 0.3, 1.0), credit)
		elif d < lethal * 1.6:
			# outside it, the blast: hurt, not killed
			n.take_hit(70.0 * (1.0 - (d - lethal) / (lethal * 0.6)), credit)
	KillFeed.cause = ""
	Sim.prof_end(&"nuke.hurt", _p3)
	if strategic and is_instance_valid(fight.mode) and fight.mode.running:
		var _p4 := Sim.prof_at()
		fight.mode._finish(true, "STRATEGIC STRIKE")
		Sim.prof_end(&"nuke.finish", _p4)

## `many` is one burst of a carpet: there are a hundred of them inside a few
## seconds, and each drawn as a bomb is -- three fireballs, two of them lamps
## reaching ninety metres, and a sound -- stopped the game while they went off
## and did less than it looked. They are drawn cheaply and hit as hard.
## A round of thirty millimetre landing: small, many, and hard on anything with
## armour. Not `bomb` -- a cannon shell is not a bomblet, and sixty of those
## booms in two seconds is a firework display rather than a gun.
func cannon(at: Vector3, picture := false) -> void:
	KillFeed.cause = "strafe"
	_cannon_hit(at, picture)
	KillFeed.cause = ""

func _cannon_hit(at: Vector3, picture := false) -> void:
	cannon_hits += 1
	var fb := Effects.Boom.new()
	fb.radius = 3.4
	fb.smoke = false
	fb.life_max = 0.35
	fb.lit = cannon_hits % 8 == 0
	fight.world.add_child(fb)
	fb.global_position = at + Vector3(0, 0.6, 0)
	if cannon_hits % 2 == 0:
		Effects.dust(fight.world, at + Vector3(0, 0.3, 0), 1.6)
	if picture:
		return
	for n in fight.soldiers.duplicate():
		if not is_instance_valid(n) or (n as Soldier).team == 0:
			continue
		var off: Vector3 = (n as Soldier).global_position - at
		off.y *= 0.5
		var d: float = off.length()
		if d < 6.5:
			(n as Soldier).take_hit(300.0 * clampf(1.15 - d / 6.5, 0.0, 1.0), fight.player)
	for v in fight.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(v) or not (v is Node3D) or v is Soldier or v == fight.player \
				or not v.has_method("take_hit") or not ("team" in v) or int(v.team) == 0:
			continue
		var dv: float = (v as Node3D).global_position.distance_to(at)
		if v.has_method("surface_gap"):
			dv = maxf(float(v.call("surface_gap", at)), 0.0)
		elif v.has_method("hit_radius"):
			dv = maxf(dv - float(v.call("hit_radius")), 0.0)
		if dv < 7.0:
			v.take_hit(130.0 * clampf(1.1 - dv / 7.0, 0.0, 1.0), fight.player)
	if is_instance_valid(fight.player) and not fight.away:
		var dp: float = fight.player.global_position.distance_to(at)
		if dp < 5.0:
			fight.player.take_hit(160.0 * (1.0 - dp / 5.0), fight.player)

## `why` is what the kill feed puts it down to.
func bomb(at: Vector3, big := 1.0, many := false, why := "strike", picture := false) -> void:
	KillFeed.cause = why
	_bomb_hit(at, big, many, picture)
	KillFeed.cause = ""

func _bomb_hit(at: Vector3, big: float, many: bool, picture := false) -> void:
	if many:
		_carpet_n += 1
		var fb := Effects.Boom.new()
		fb.radius = 6.0
		fb.smoke = false
		fb.life_max = 0.45
		fb.lit = _carpet_n % 6 == 0
		fight.world.add_child(fb)
		fb.global_position = at + Vector3(0, 1.0, 0)
		var sm := Effects.Boom.new()
		sm.radius = 7.0
		sm.tint = Color(0.20, 0.19, 0.18)
		sm.smoke = false
		sm.lit = false
		sm.life_max = 1.4
		fight.world.add_child(sm)
		sm.global_position = at + Vector3(0, 2.5, 0)
		if _carpet_n % 3 == 0:
			Sfx.play_at(fight.world, "boom", at, -4.0, randf_range(0.8, 1.1), 4500.0)
	else:
		Effects.mute_blast = true
		Effects.explosion(fight.world, at + Vector3(0, 1.0, 0), 5.0 * big)
		Effects.he_impact(fight.world, at + Vector3(0, 0.6, 0), 4.5 * big)
		Effects.mute_blast = false
	if picture:
		return                         # the look of it; the damage was dealt where it was called
	var kill_r: float = 14.0 * big
	for n in fight.soldiers.duplicate():
		if not is_instance_valid(n) or (n as Soldier).team == 0:
			continue
		# Height counts for less than distance along the street: a bomblet
		# that goes off on a roof is still over the man under the eaves.
		var off: Vector3 = (n as Soldier).global_position - at
		off.y *= 0.35
		var d: float = off.length()
		if d < kill_r:
			(n as Soldier).take_hit(320.0 * pow(1.0 - d / kill_r, 1.1), fight.player)
	# and whatever of theirs is parked in it
	for v in fight.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(v) or not (v is Node3D) or v is Soldier or v == fight.player \
				or not v.has_method("take_hit") or not ("team" in v) or int(v.team) == 0:
			continue
		var dv: float = (v as Node3D).global_position.distance_to(at)
		if dv < kill_r * 0.7:
			v.take_hit(140.0 * big * (1.0 - dv / (kill_r * 0.7)), fight.player)
	if is_instance_valid(fight.player) and not fight.away:
		var dp: float = fight.player.global_position.distance_to(at)
		if dp < 9.0 * big:
			fight.player.take_hit(160.0 * (1.0 - dp / (9.0 * big)), fight.player)
