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

const LONG := ["carbine", "ak", "scar", "smg", "vector", "shotgun", "lmg", "dmr", "sniper"]
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
	_sight = _choice(mid, "SIGHT", [])
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

func _choice(into: Control, label: String, ids: Array) -> OptionButton:
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
		for k in Tank.KINDS:
			var kd: Dictionary = Tank.KINDS[k]
			if String(kd.get("faction", "")) != faction:
				continue
			if String(kd.get("class", "")) in ["tel", "asat", "sam", "mlrs", "spg"]:
				continue            # nothing that fights from twenty kilometres away
			_add_ride("veh:" + String(k), String(kd["name"]))
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
	_sight.select(maxi(Firearm.SIGHTS.find(String(c["sight"])), 0))
	_quiet.button_pressed = bool(c["quiet"])
	_grip.button_pressed = bool(c["grip"])
	_mag.button_pressed = bool(c["mag"])
	_filling = false
	_note.text = String(c.get("note", ""))
	_show_stats(c)

## Something on the bench was changed: write it back into the class.
func _changed() -> void:
	if _filling:
		return
	var c: Dictionary = CqbMatch.kit_classes()[CqbMatch.class_pick]
	c["primary"] = LONG[_primary.selected]
	c["second"] = SECOND[_second.selected]
	if c["second"] == c["primary"]:
		c["second"] = "smg" if c["primary"] != "smg" else "carbine"
		_filling = true
		_second.select(SECOND.find(String(c["second"])))
		_filling = false
	c["sight"] = Firearm.SIGHTS[_sight.selected]
	c["quiet"] = _quiet.button_pressed
	c["grip"] = _grip.button_pressed
	c["mag"] = _mag.button_pressed
	_show_stats(c)

func _show_stats(c: Dictionary) -> void:
	var g: Dictionary = Firearm.fitted(String(c["primary"]), c)
	var base: Dictionary = Firearm.spec(String(c["primary"]))
	var s2: Dictionary = Firearm.spec(String(c["second"]))
	var quiet: bool = bool(c["quiet"]) and Firearm.can_suppress(g)
	_stats.text = "%s\n  damage %d%s   %d rpm   magazine %d\n  recoil %d%%   sight %s   %s\n\n%s\n  %s" % [
		String(g["name"]), int(float(g["dmg"])),
		" x%d" % int(g["pellets"]) if int(g["pellets"]) > 1 else "",
		int(60.0 / float(g["cd"])), int(g["mag"]),
		int(float(g["kick"]) / float(base["kick"]) * 100.0),
		"%.1fx" % (74.0 / float(g["fov"])),
		"heard at 14 m" if quiet else "heard at 75 m",
		String(s2["name"]),
		"three rockets: armour, walls, anything" if String(s2.get("launcher", "")) == "rocket"
		else ("two missiles: aircraft only, needs a lock" if String(s2.get("launcher", "")) == "sam"
		else ("six 40 mm rounds in the drum, twelve more: they arc, and burst past ten metres"
			if String(s2.get("launcher", "")) == "gl"
		else "magazine %d, %d rpm" % [int(s2["mag"]), int(60.0 / float(s2["cd"]))]))]

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
