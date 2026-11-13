class_name DeployMenu
extends Control
## The screen between being dead and being back in it: what to go in as.
##
## This is where a class is chosen and where it is changed. It was all on the
## hangar screen -- a row of dropdowns under the mission buttons -- which is
## the wrong place twice over: you had to leave the match to change a sight,
## and the hangar had to know about rifles. Here it comes up when the match
## starts and every time you go down, and what you set a class up as stays
## that way for the session.

signal deploy(what: String)

var _class_btns: Array = []
var _primary: OptionButton
var _second: OptionButton
## Which of the two the sight, can, grip and magazine below are being fitted
## to: 0 the primary, 1 the second. Each weapon has its own.
var _bench := 0
var _bench_btns: Array = []
var _sight: OptionButton
var _quiet: CheckButton
var _grip: CheckButton
var _mag: CheckButton
var _note: Label
var _stats: Label
var _rides: ItemList
var _ride_ids: Array = []
var _ride_box: VBoxContainer
var _filling := false
var _streak_ticks := {}
var _streak_note: Label

const LONG := ["carbine", "ak", "scar", "smg", "vector", "shotgun", "lmg", "dmr", "sniper", "fifty"]
const SECOND := ["smg", "vector", "glock", "carbine", "shotgun", "gl", "law", "stinger"]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 520)
	centre.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(pad)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	pad.add_child(root)
	root.add_child(_head("DEPLOY", 30))
	# The columns scroll. The killstreak list made the panel taller than a
	# laptop screen, and a panel in a centre container just grows off both
	# ends of it: the bottom ticks and the DEPLOY button could not be reached.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var fit := func():
		var vs: Vector2 = get_viewport_rect().size
		panel.custom_minimum_size = Vector2(minf(980.0, vs.x - 40.0),
			clampf(vs.y - 60.0, 320.0, 860.0))
	resized.connect(fit)
	fit.call()

	# ---- the classes
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(_head("CLASS", 14))
	var all: Array = CqbMatch.kit_classes()
	for i in all.size():
		var b := Button.new()
		b.text = String(all[i]["name"])
		b.custom_minimum_size = Vector2(220, 44)
		b.pressed.connect(_pick.bind(i))
		left.add_child(b)
		_class_btns.append(b)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(220, 70)
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", Color(0.7, 0.8, 0.88))
	left.add_child(_note)

	# ---- the gunsmith
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(330, 0)
	mid.add_theme_constant_override("separation", 8)
	cols.add_child(mid)
	mid.add_child(_head("GUNSMITH — this class, as you want it", 14))
	_primary = _choice(mid, "PRIMARY", LONG)
	_second = _choice(mid, "SECOND", SECOND)
	# one weapon on the bench at a time: what is below is fitted to it alone
	var bench := HBoxContainer.new()
	bench.add_theme_constant_override("separation", 6)
	mid.add_child(bench)
	var bl := Label.new()
	bl.text = "FITTING"
	bl.custom_minimum_size = Vector2(84, 0)
	bl.add_theme_font_size_override("font_size", 13)
	bench.add_child(bl)
	for bi in 2:
		var bb := Button.new()
		bb.custom_minimum_size = Vector2(115, 30)
		bb.add_theme_font_size_override("font_size", 12)
		bb.clip_text = true
		bb.pressed.connect(_to_bench.bind(bi))
		bench.add_child(bb)
		_bench_btns.append(bb)
	_sight = _choice(mid, "SIGHT", [], false)
	for sgt in Firearm.SIGHTS:
		_sight.add_item(String(Firearm.SIGHT_NAMES[sgt]))
	_quiet = _tick(mid, "Suppressor — quiet, no flash, a little slower")
	_grip = _tick(mid, "Foregrip — less climb, less wander")
	_mag = _tick(mid, "Extended magazine — half as many again, slower to change")
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	mid.add_child(_stats)

	# ---- what a run of kills buys: up to four, carried into every life
	mid.add_child(_head("KILLSTREAKS — up to %d, spent with 4 to 7" % CqbMatch.MAX_STREAKS, 14))
	for k in CqbMatch.STREAK_POOL:
		var t := CheckButton.new()
		t.text = "%-16s %d kills" % [String(k["name"]), int(k["at"])]
		t.tooltip_text = String(k["note"])
		t.add_theme_font_size_override("font_size", 13)
		t.toggled.connect(_streak_toggled.bind(String(k["id"])))
		mid.add_child(t)
		_streak_ticks[String(k["id"])] = t
	_streak_note = Label.new()
	_streak_note.add_theme_font_size_override("font_size", 12)
	_streak_note.add_theme_color_override("font_color", Color(0.7, 0.8, 0.88))
	mid.add_child(_streak_note)

	# ---- what to go in
	_ride_box = VBoxContainer.new()
	_ride_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ride_box.add_theme_constant_override("separation", 6)
	cols.add_child(_ride_box)
	_ride_box.add_child(_head("GO IN", 14))
	_rides = ItemList.new()
	_rides.custom_minimum_size = Vector2(300, 330)
	_rides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ride_box.add_child(_rides)

	var go := Button.new()
	go.text = "DEPLOY"
	go.custom_minimum_size = Vector2(240, 54)
	go.add_theme_font_size_override("font_size", 20)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(_go)
	root.add_child(go)
	visible = false

func _head(t: String, points: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", points)
	l.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	return l

func _choice(into: Control, label: String, ids: Array, weapon := true) -> OptionButton:
	var row := HBoxContainer.new()
	into.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(84, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(236, 32)
	for id in ids:
		ob.add_item(String(Firearm.spec(String(id))["name"]))
	# a different weapon is a different thing on the bench; a different sight
	# is a change to the one that is there
	if weapon:
		ob.item_selected.connect(func(_i: int): _weapon_changed())
	else:
		ob.item_selected.connect(func(_i: int): _changed())
	row.add_child(ob)
	return ob

func _tick(into: Control, label: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.add_theme_font_size_override("font_size", 13)
	c.toggled.connect(func(_on: bool): _changed())
	into.add_child(c)
	return c

## Show it. `takes` is what the mode lets you bring ("none", "ground", "any")
## and `first` is whether the match has not started yet -- the only time
## changing aeroplane costs nothing.
func open(takes: String, first: bool, faction: String) -> void:
	_rides.clear()
	_ride_ids.clear()
	_add_ride("foot", "ON FOOT — as the class on the left")
	if takes == "ground" or takes == "any":
		# Every tank, fighting vehicle, gun carrier and scout car there is,
		# his own country's first. It was his own country's alone, which was
		# four vehicles; the heavy end of the list is the same on every side
		# and there is no reason a man cannot be handed somebody else's.
		var mine: Array = []
		var theirs: Array = []
		for k in Tank.KINDS:
			var kd: Dictionary = Tank.KINDS[k]
			if String(kd.get("class", "")) in ["tel", "asat", "sam", "mlrs", "spg"]:
				continue            # nothing that fights from twenty kilometres away
			if String(kd.get("faction", "")) == faction:
				mine.append(k)
			else:
				theirs.append(k)
		var order := ["mbt", "ifv", "spaag", "lav"]
		var by_class := func(x, y) -> bool:
			return order.find(String(Tank.KINDS[x].get("class", ""))) \
				< order.find(String(Tank.KINDS[y].get("class", "")))
		mine.sort_custom(by_class)
		theirs.sort_custom(by_class)
		var tags := {"mbt": "tank", "ifv": "fighting vehicle", "spaag": "anti-air gun", "lav": "scout car"}
		for k in mine + theirs:
			var kd2: Dictionary = Tank.KINDS[k]
			_add_ride("veh:" + String(k), "%s — %s" % [String(kd2["name"]),
				String(tags.get(String(kd2.get("class", "")), ""))])
	if takes == "any" and first:
		for id in JetSpec.ids_for(faction):
			var sp := JetSpec.get_spec(id)
			_add_ride(String(id), "%s — %s" % [String(sp["name"]), String(sp["role"])])
	_ride_box.visible = _ride_ids.size() > 1
	_rides.select(0)
	_pick(CqbMatch.class_pick)
	_show_streaks()
	visible = true

func _add_ride(id: String, text: String) -> void:
	_rides.add_item(text)
	_ride_ids.append(id)

func _pick(i: int) -> void:
	var all: Array = CqbMatch.kit_classes()
	CqbMatch.class_pick = clampi(i, 0, all.size() - 1)
	var c: Dictionary = all[CqbMatch.class_pick]
	for k in _class_btns.size():
		(_class_btns[k] as Button).modulate = Color(0.55, 1.0, 0.75) if k == CqbMatch.class_pick \
			else Color(1, 1, 1)
	_filling = true
	_primary.select(maxi(LONG.find(String(c["primary"])), 0))
	_second.select(maxi(SECOND.find(String(c["second"])), 0))
	_filling = false
	_note.text = String(c.get("note", ""))
	_to_bench(_bench)

## The weapon that is on the bench: the class's primary or its second.
func _bench_id(c: Dictionary) -> String:
	return String(c["second"] if _bench == 1 else c["primary"])

## Put one of the two on the bench and show how it is fitted.
func _to_bench(which: int) -> void:
	_bench = which
	var c: Dictionary = CqbMatch.kit_classes()[CqbMatch.class_pick]
	for k in _bench_btns.size():
		var b: Button = _bench_btns[k]
		b.text = String(Firearm.spec(String(c["second"] if k == 1 else c["primary"]))["name"])
		b.modulate = Color(0.55, 1.0, 0.75) if k == _bench else Color(1, 1, 1)
	var id: String = _bench_id(c)
	var g: Dictionary = Firearm.spec(id)
	var s: Dictionary = Firearm.setup_for(c, id)
	# a tube or a pistol takes nothing; a shotgun takes no can
	var bare: bool = g.has("launcher") or bool(g.get("hand", false))
	_filling = true
	_sight.select(maxi(Firearm.SIGHTS.find(String(s["sight"])), 0))
	_quiet.button_pressed = bool(s["quiet"]) and Firearm.can_suppress(g)
	_grip.button_pressed = bool(s["grip"]) and not bare
	_mag.button_pressed = bool(s["mag"]) and not bare
	_filling = false
	_sight.disabled = bare
	_quiet.disabled = not Firearm.can_suppress(g)
	_grip.disabled = bare
	_mag.disabled = bare
	_show_stats(c)

## A different weapon was chosen for one of the two slots. What is fitted to
## it is whatever was last fitted to *it*, not what the one before it wore.
func _weapon_changed() -> void:
	if _filling:
		return
	var c: Dictionary = CqbMatch.kit_classes()[CqbMatch.class_pick]
	var was_primary: String = String(c["primary"])
	c["primary"] = LONG[_primary.selected]
	c["second"] = SECOND[_second.selected]
	if c["second"] == c["primary"]:
		c["second"] = "smg" if c["primary"] != "smg" else "carbine"
		_filling = true
		_second.select(SECOND.find(String(c["second"])))
		_filling = false
	_to_bench(0 if String(c["primary"]) != was_primary else 1)

## Something on the bench was changed: write it into that weapon's own setup.
func _changed() -> void:
	if _filling:
		return
	var c: Dictionary = CqbMatch.kit_classes()[CqbMatch.class_pick]
	var s: Dictionary = Firearm.setup_for(c, _bench_id(c), true)
	s["sight"] = Firearm.SIGHTS[_sight.selected]
	s["quiet"] = _quiet.button_pressed
	s["grip"] = _grip.button_pressed
	s["mag"] = _mag.button_pressed
	_show_stats(c)

## One weapon as it is fitted, in two lines.
func _stat_lines(c: Dictionary, id: String) -> String:
	var base: Dictionary = Firearm.spec(id)
	var launcher: String = String(base.get("launcher", ""))
	if launcher == "rocket":
		return "%s\n  three rockets: armour, walls, anything" % String(base["name"])
	if launcher == "sam":
		return "%s\n  two missiles: aircraft only, needs a lock" % String(base["name"])
	if launcher == "gl":
		return "%s\n  six 40 mm rounds in the drum, twelve more: they arc, and burst past ten metres" \
			% String(base["name"])
	var g: Dictionary = Firearm.fitted(id, Firearm.setup_for(c, id))
	var pen: float = Firearm.pen_of(g)
	return "%s\n  damage %d%s   %d rpm   magazine %d\n  recoil %d%%   sight %s   %s\n  goes through %s" % [
		String(g["name"]), int(float(g["dmg"])),
		" x%d" % int(g["pellets"]) if int(g["pellets"]) > 1 else "",
		int(60.0 / float(g["cd"])), int(g["mag"]),
		int(float(g["kick"]) / float(base["kick"]) * 100.0),
		"%.1fx" % (74.0 / float(g["fov"])),
		"heard at 14 m" if bool(g.get("quiet", false)) else "heard at 75 m",
		"walls, cars and several men" if pen >= 1.0
		else ("a house wall, or two men" if pen >= 0.6
		else ("a thin wall or a fence, or one man" if pen >= 0.3
		else "planks and not much else"))]

func _show_stats(c: Dictionary) -> void:
	_stats.text = "%s\n\n%s" % [_stat_lines(c, String(c["primary"])),
		_stat_lines(c, String(c["second"]))]

## One ticked or unticked. A fifth is refused rather than quietly dropping
## one of the others, and the last one cannot be taken off -- a man with
## nothing to earn plays a different game.
func _streak_toggled(on: bool, id: String) -> void:
	if _filling:
		return
	var pick: Array = CqbMatch.streak_pick
	if on and not pick.has(id):
		if pick.size() >= CqbMatch.MAX_STREAKS:
			_filling = true
			(_streak_ticks[id] as CheckButton).button_pressed = false
			_filling = false
			_streak_note.text = "four at most: take one off first"
			return
		pick.append(id)
	elif not on and pick.has(id):
		if pick.size() <= 1:
			_filling = true
			(_streak_ticks[id] as CheckButton).button_pressed = true
			_filling = false
			_streak_note.text = "carry at least one"
			return
		pick.erase(id)
	_show_streaks()

func _show_streaks() -> void:
	_filling = true
	for id in _streak_ticks:
		(_streak_ticks[id] as CheckButton).button_pressed = CqbMatch.streak_pick.has(id)
	_filling = false
	var keys := PackedStringArray()
	for k in CqbMatch.chosen_streaks():
		keys.append("%d %s" % [int(k["key"]), String(k["name"])])
	_streak_note.text = "   ".join(keys)

func _go() -> void:
	var picked: PackedInt32Array = _rides.get_selected_items()
	var id: String = "foot" if picked.is_empty() else String(_ride_ids[picked[0]])
	visible = false
	deploy.emit(id)
