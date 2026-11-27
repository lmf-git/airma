class_name HudKeys
extends RefCounted
## The key card: which keys do what in the seat you are in -- on foot, in a hold, under a canopy, driving, sailing, at the conn, in a rocket, flying a jet or a helicopter -- and when the card has to change. Split out of `hud.gd`; the HUD has one as `keys`.

var h: HUD

## What the card is currently showing, as one integer: which seat, and the two
## things a ship's list depends on. Compared every frame, which costs nothing;
## the list is only rebuilt and redrawn when it differs.
var _card_sig := ""



func _init(owner_node: HUD) -> void:
	h = owner_node

func _ship_keys() -> Array:
	var conn := [
		["A / D", "wheel: port / starboard"],
		["W / S", "telegraph: ahead / astern"],
		["P", "view: conning tower / close / chase / wide"],
		["RMB (hold)", "zoom the view"],
		["N", "night vision"],
		["M", "tactical map"],
		["U", "hand over the conn"],
	]
	if h.ship.can_dive():
		conn.append(["F / R", "dive / surface"])
	var arms := [
		["1 - 2", "select weapon by number"],
		["\\", "cycle weapon"],
		["T", "cycle target"],
		["SPACE", "fire the selected weapon"],
		["O", "sensor page"],
		["I", "sensor channel"],
		["L", "laser"],
		["CTRL + T", "track what the sight is on"],
	]
	if h.ship.can_launch():
		arms.append(["RMB on the map", "lay the strategic aiming point"])
	if not h.ship.armed():
		# A merchant hull, or a boat with her tubes shot dry: the sensor is
		# still hers, the weapon keys are not.
		return [["THE CONN", conn], ["SENSOR", [
			["O", "sensor page"],
			["I", "sensor channel"],
			["CTRL + T", "track what the sight is on"],
		]], ["GENERAL", _general_keys()]]
	return [["THE CONN", conn], ["WEAPONS", arms], ["GENERAL", _general_keys()]]

## The carrier's bridge. She has nothing to fire, so the card says so by
## leaving it off: the aeroplane's card stood here before, offering a gun, a
## weapon select and a gunner station on a ship that carries none of them.
func _conn_keys() -> Array:
	return [["THE CONN", [
		["A / D", "wheel: port / starboard"],
		["W / S", "telegraph: ahead / astern"],
		["mouse", "look out from the island"],
		["RMB (hold)", "zoom the view"],
		["O / ALT+RMB", "sensor page"],
		["TAB", "sensor, all stop, amidships, hand over"],
		["M", "tactical map"],
		["U", "hand over the conn"],
	]], ["GENERAL", _general_keys()]]

func _rocket_keys() -> Array:
	return [["THE ROCKET", [
		["SHIFT / CTRL", "throttle up / down"],
		["X", "engine cut"],
		["W / S", "pitch"],
		["Q / E", "yaw"],
		["A / D", "roll"],
		["T", "attitude: free, hold, prograde, retrograde"],
		["H", "autopilot: to orbit; in the moon rocket, on to the moon"],
		["SPACE", "drop the spent stage, light the next"],
		[", / .", "time warp, coasting above the air"],
		["mouse / wheel", "look round / closer and further"],
		["U", "climb out, once it is down"],
	]], ["TO ORBIT", [
		["1", "full throttle, straight up"],
		["2", "from a kilometre up, lean east a little at a time"],
		["3", "past 40 km, T to PROGRADE and let it follow"],
		["4", "cut when LOW POINT passes 150 km"],
	]], ["GENERAL", _general_keys()]]

func _tank_keys() -> Array:
	var t: Tank = h.tank as Tank
	var drive: Array = [
		["W / S", "throttle ahead / astern"],
		["A / D", "steer"],
		["X", "brake"],
		["P", "view"],
		["N", "night vision"],
		["M", "tactical map"],
		["U", "dismount"],
	]
	var gun: Array = [["mouse", "lay the turret"]]
	var ws: PackedStringArray = t.weapons() if t != null else PackedStringArray()
	if ws.size() > 1:
		gun.append(["1 - %d  or  \\" % ws.size(), "select / cycle weapon"])
	if t != null and t.is_indirect():
		gun.append(["RMB on the map", "lay a fire mission by grid"])
		gun.append(["SPACE / LMB", "fire on the mission" + ("  ( a ripple )" if t.is_ripple() else "")])
		gun.append(["TAB", "cancel the fire mission"])
	elif t != null and t.is_air_defence():
		gun.append(["SPACE / LMB", "fire: the gun leads, the missile wants a lock"])
	else:
		gun.append(["SPACE / LMB", "fire"])
		if t != null and t.has_coax():
			gun.append(["K", "coaxial machine gun"])
	gun.append(["O", "the sight"])
	return [
		["DRIVING", drive],
		["THE GUN" if t == null or not t.is_indirect() else "FIRE MISSION", gun],
		["GENERAL", _general_keys()],
	]

func _foot_keys() -> Array:
	var w: Walker = h.walker as Walker
	var in_hold: bool = w != null and is_instance_valid(w.frame)
	var gunship: bool = in_hold and is_instance_valid(w.frame_owner) \
		and "spec" in w.frame_owner and bool(w.frame_owner.spec.get("gunship", false))
	var move: Array = [
		["WASD", "walk"],
		["SHIFT", "sprint  ( weapon down, spends wind )"],
		["C / CTRL", "crouch on and off  ( from a sprint: slide )"],
		["Z", "prone on and off"],
		["SPACE", "jump  /  vault  /  climb  —  at a tall wall: take hold of it"],
		["on a wall", "W S A D climb, SHIFT faster, SPACE kick off, C let go"],
		["Q / E", "lean left / right"],
		["F", "pick up a dropped weapon"],
		["U", "board what you are standing at"],
	]
	if w != null and w.chute:
		move = [["under canopy", "A D turn, W run on and sink, S brake and hold up"]]
	elif in_hold:
		move = [
			["WASD", "walk about the hold"],
			["ramp", "walk off the end of the open ramp to jump"],
		]
		if gunship:
			move.append(["G", "take a gun station"])
	var groups: Array = [
		["ON FOOT" if not in_hold else "IN THE HOLD", move],
		["WEAPONS", [
			["LMB", "fire"],
			["RMB", "sights"],
			["WHEEL", "on the sights: a variable scope's power"],
			["↑ ↓ ← →", "on the sights: dial elevation and windage"],
			["V", "fire mode"],
			["1 - 3", "the two long guns and the sidearm"],
			["R", "reload"],
			["G", "grenade"],
			["X", "flashbang"],
		]],
	]
	if _carries_mortar() and not in_hold:
		groups.append(["MORTAR", [
			["LMB", "set it up where you stand  ( stand still )"],
			["RMB", "plot a fire mission on the map, 80 – 820 m"],
			["LMB", "once laid: a round onto the mission"],
			["move", "packs it up again"],
		]])
	var view: Array = [
		["P", "first person / over the shoulder"],
		["B", "binoculars"],
		["N", "night vision"],
		["M", "map — wheel zooms right in to the streets"],
		["TAB", "orders"],
	]
	if is_instance_valid(w) and is_instance_valid(w.arena):
		view.append(["4 - 7", "kill streaks, cheapest first — chosen on the deploy screen"])
		view.append(["", "airstrike and fire mission open the map: click the spot"])
	groups.append(["VIEW", view])
	groups.append(["GENERAL", _general_keys()])
	return groups

func _carries_mortar() -> bool:
	if h.walker == null or not is_instance_valid(h.walker):
		return false
	var w: Walker = h.walker as Walker
	for i in w.slots:
		if String(w.spec_of(int(i)).get("launcher", "")) == "mortar":
			return true
	return false

func _general_keys() -> Array:
	return [
		["F2", "this card"],
		["F3", "admin"],
		["F4", "satellite view: the planet from orbit"],
		["/", "chat"],
		["ESC", "back out: map, satellite view, then menu"],
	]

func _air_keys() -> Array:
	var live: bool = is_instance_valid(h.aircraft)
	var sp: Dictionary = (h.aircraft as Aircraft).spec if live else {}
	var heli: bool = (live and h.aircraft is Helicopter) or bool(sp.get("rotary", false))
	var fly: Array
	if heli:
		fly = [
			["W / S", "cyclic forward / back"],
			["A / D", "cyclic left / right"],
			["Q / E", "pedals: yaw left / right"],
			["SHIFT / CTRL", "collective up / down  ( let go: it holds the height )"],
			[";", "mouse as cyclic  ( ALT + mouse: look around )"],
		]
	else:
		fly = [
			["W / S", "pitch down / up"],
			["A / D", "roll left / right"],
			["Q / E", "rudder"],
			["SHIFT / CTRL", "throttle + afterburner"],
			[";", "mouse as stick  ( ALT + mouse: look around )"],
		]
		if bool(sp.get("stovl", false)):
			fly.append(["H", "jetborne / wingborne  ( STOVL )"])
	var ground: Array = [["G", "landing gear up / down"],
		["X", "wheel brakes" + ("" if heli else " / airbrake")]]
	if not heli:
		ground.append(["F", "flaps"])
	if bool(sp.get("gunship", false)):
		ground.append(["J", "gunner station"])
	var arms: Array = [
		["1 - 8", "select weapon by number"],
		["\\", "cycle weapon"],
		["T", "cycle target"],
		["LMB / SPACE", "fire selected weapon"],
		["K", "gun burst"],
		["C", "flares"],
		["V", "chaff"],
	]
	# doors to open, not pylons, which are listed with the bays and are always ready
	if (sp.get("bays", []) as Array).any(func(b): return String(b.get("kind", "")) == "internal"):
		arms.insert(2, ["B", "open + close weapon bay"])
	return [
		["HELICOPTER" if heli else "FLYING", fly],
		["ON THE GROUND", ground],
		["WEAPONS", arms],
		["SENSORS", [
			["RMB (hold)", "zoom the view"],
			["O / ALT+RMB", "raise / stow the sensor page"],
			["CTRL+T", "designate  ( point track )"],
			["L", "laser  ( lamp with the page stowed )"],
			["N", "sensor channel / night vision"],
			["[  ]", "left / right side panels"],
			["=  -", "radar range"],
		]],
		["VIEW", [
			["P", "cockpit / chase / orbit"],
			["ALT + mouse", "look around"],
			["Y", "weapon camera"],
			["M", "map"],
			["TAB", "aircraft actions"],
			["F3", "air traffic: call aircraft in to land"],
		]],
		["GENERAL", _general_keys()],
	]



## Which keys apply where you are sitting, and whether that has changed.
func _refresh_help() -> void:
	if h._card == null:
		return
	var sig: String = _seat_sig() if h.show_help else "off"
	if sig == _card_sig:
		return
	_card_sig = sig
	h._card.visible = h.show_help
	if not h.show_help:
		return
	match sig.get_slice(":", 0):
		"rocket":
			h._card.show_keys(_rocket_keys())
		"conn":
			h._card.show_keys(_conn_keys())
		"ship":
			h._card.show_keys(_ship_keys())
		"tank":
			h._card.show_keys(_tank_keys())
		"foot":
			var keys: Array = _foot_keys()
			# on the range, its own keys first: the slow-motion bullet camera is
			# the reason to be there and nothing on the card said how to get it
			if h.mode != null and is_instance_valid(h.mode) and String(h.mode.get("mode")) == "range":
				keys = [["FIRING RANGE", [
					["Y", "slow-motion bullet camera: rides your next round to the board"],
					["PgUp / PgDn", "slow-motion speed"],
					["T", "trace lines: each round's flight, and its drop off the bore line"],
					["BACKSPACE", "clear the boards and the traces"],
					["F", "take a weapon off the rack behind the line"],
				]]] + keys
			h._card.show_keys(keys)
		_:
			h._card.show_keys(_air_keys())

## Where you are, as far as the key card cares: the seat, and whatever about it
## changes which keys do something -- the airframe, a ship's tubes, a man in a
## hold or under a canopy, a mortar in his kit. Compared every frame, which
## costs nothing; the card is only rebuilt when it differs. It was the seat
## alone, so a helicopter got the jet's flaps and bay, and a man in a hold or
## hanging under a canopy got the whole of the street.
func _seat_sig() -> String:
	if h.rocket != null and is_instance_valid(h.rocket):
		return "rocket"
	if h.carrier != null and is_instance_valid(h.carrier):
		return "conn"
	if h.ship != null and is_instance_valid(h.ship):
		return "ship:%s%s%s" % [h.ship.can_dive(), h.ship.can_launch(), h.ship.armed()]
	if h.tank != null and is_instance_valid(h.tank):
		return "tank:%s" % String(h.tank.get("kind")) if "kind" in h.tank else "tank"
	if h.walker != null and is_instance_valid(h.walker):
		var w: Walker = h.walker as Walker
		return "foot:%s%s%s%s" % [w.chute, is_instance_valid(w.frame), _carries_mortar(),
			is_instance_valid(w.arena)]
	if is_instance_valid(h.aircraft):
		# the airframe itself: a spec carries no name of its own
		return "air:%d" % h.aircraft.get_instance_id()
	return "air:"
