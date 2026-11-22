class_name DeployMenu
extends Control
## The screen between being dead and being back in it: what to go in as.
##
## Four pages under one header. CLASS picks which of the classes to go in as,
## each a card with its weapons drawn on it. GUNSMITH is that class's own
## page: its name, its two weapons, the one on the bench turning on a stand,
## what is fitted to it and what that does to it. KILLSTREAKS is the whole
## list as cards with their icons, four of them carried. VEHICLE is what can
## be brought in instead of walking. Along the bottom, always, the class as it
## stands, the streaks carried, and DEPLOY.
##
## What a class is set up as stays that way for the session.

signal deploy(what: String)
## A side chosen, BLUE 0 or RED 1, in a session in a mode with sides.
signal side_picked(abs_side: int)

const LONG := ["carbine", "ak", "scar", "smg", "vector", "shotgun", "aa20", "lmg", "dmr", "sniper",
	"fifty"]
const SECOND := ["smg", "vector", "glock", "carbine", "shotgun", "aa20", "gl", "law", "stinger", "mortar"]

# ------------------------------------------------------------------ the look
const BG := Color(0.035, 0.045, 0.06, 0.94)
const CARD := Color(0.075, 0.095, 0.12)
const CARD_HI := Color(0.10, 0.14, 0.18)
const EDGE := Color(0.20, 0.27, 0.33)
const ACCENT := Color(0.38, 0.86, 1.0)
const GOOD := Color(0.50, 1.0, 0.70)
const TEXT := Color(0.86, 0.92, 0.97)
const DIM := Color(0.56, 0.64, 0.72)

var _tabs: Array = []
var _pages: Array = []
var _page := 0

# CLASS
var _class_btns: Array = []
var _class_cards: Array = []
var _note: Label

# GUNSMITH
var _name_edit: LineEdit
var _primary: OptionButton
var _second: OptionButton
var _bench := 0
var _bench_btns: Array = []
var _sight: OptionButton
var _quiet: CheckButton
var _grip: CheckButton
var _mag: CheckButton
var _choke: OptionButton
var _slug: CheckButton
var _stats: Label
var _bars: Dictionary = {}
var _stand: SubViewport = null
var _stand_pivot: Node3D = null
var _stand_gun: Node3D = null
var _turn_t := 0.0

# KILLSTREAKS
var _streak_ticks := {}
var _streak_cards := {}
var _streak_note: Label

# VEHICLE
var _rides: ItemList
var _ride_ids: Array = []
var _ride_box: Control

# the bar along the bottom
var _sum_class: Label
var _sum_weapons: Label
var _sum_streaks: HBoxContainer

var _filling := false

func _ready() -> void:
	# anchored and sized to the screen: anchors alone, set before it has a
	# parent to measure, left it a corner-sized box and the panel off-centre
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.01, 0.02, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var centre := CenterContainer.new()
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(BG, EDGE, 10, 1))
	centre.add_child(panel)
	var fit := func():
		var vs: Vector2 = get_viewport_rect().size
		panel.custom_minimum_size = Vector2(minf(1180.0, vs.x - 32.0), clampf(vs.y - 48.0, 420.0, 820.0))
	resized.connect(fit)
	fit.call()
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(pad)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	pad.add_child(root)

	# ---- header: the title and the tabs
	# Which side, in a session: asked here, where the match starts and where
	# everyone comes back to, rather than only in the hangar beforehand.
	_side_row = HBoxContainer.new()
	_side_row.add_theme_constant_override("separation", 10)
	_side_row.visible = false
	var side_lbl := _label("JOIN", 18, DIM)
	_side_row.add_child(side_lbl)
	for sd in [0, 1]:
		var sb := Button.new()
		sb.custom_minimum_size = Vector2(190, 40)
		sb.toggle_mode = true
		sb.add_theme_font_size_override("font_size", 16)
		sb.pressed.connect(_pick_side.bind(sd))
		_side_row.add_child(sb)
		_side_btns.append(sb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	root.add_child(_side_row)
	var title := _label("DEPLOY", 28, ACCENT)
	title.custom_minimum_size = Vector2(170, 0)
	head.add_child(title)
	for t in ["CLASS", "GUNSMITH", "KILLSTREAKS", "VEHICLE"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(150, 40)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_show_page.bind(_tabs.size()))
		head.add_child(b)
		_tabs.append(b)

	# ---- the pages, one at a time
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(stack)
	_pages.append(_build_class_page())
	_pages.append(_build_gunsmith_page())
	_pages.append(_build_streak_page())
	_pages.append(_build_vehicle_page())
	for p in _pages:
		(p as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)

	# ---- along the bottom: the class as it stands, the streaks, DEPLOY
	var foot := PanelContainer.new()
	foot.add_theme_stylebox_override("panel", _box(CARD, EDGE, 8, 1))
	root.add_child(foot)
	var fp := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		fp.add_theme_constant_override("margin_" + side, 12)
	foot.add_child(fp)
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 18)
	fp.add_child(fr)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.add_child(who)
	_sum_class = _label("", 18, TEXT)
	who.add_child(_sum_class)
	_sum_weapons = _label("", 13, DIM)
	who.add_child(_sum_weapons)
	_sum_streaks = HBoxContainer.new()
	_sum_streaks.add_theme_constant_override("separation", 8)
	fr.add_child(_sum_streaks)
	var go := Button.new()
	go.text = "DEPLOY"
	go.custom_minimum_size = Vector2(220, 56)
	go.add_theme_font_size_override("font_size", 22)
	go.add_theme_stylebox_override("normal", _box(Color(0.10, 0.32, 0.22), GOOD, 8, 2))
	go.add_theme_stylebox_override("hover", _box(Color(0.13, 0.42, 0.28), GOOD, 8, 2))
	go.add_theme_stylebox_override("pressed", _box(Color(0.08, 0.26, 0.18), GOOD, 8, 2))
	go.pressed.connect(_go)
	fr.add_child(go)

	_show_page(0)
	visible = false

# -------------------------------------------------------------- page: CLASS
func _build_class_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.add_child(_label("Choose what to go in as. GUNSMITH changes the one chosen.", 13, DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var all: Array = CqbMatch.kit_classes()
	for i in all.size():
		var card := Button.new()
		card.custom_minimum_size = Vector2(340, 168)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.toggle_mode = true
		card.pressed.connect(_pick.bind(i))
		var inner := VBoxContainer.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 14
		inner.offset_top = 10
		inner.offset_right = -14
		inner.offset_bottom = -10
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("separation", 4)
		card.add_child(inner)
		var nm := _label("", 17, TEXT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(nm)
		var art := WeaponArt.new()
		art.custom_minimum_size = Vector2(0, 52)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(art)
		var wl := _label("", 12, DIM)
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(wl)
		var nt := _label("", 12, Color(0.66, 0.75, 0.82))
		nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(nt)
		grid.add_child(card)
		_class_btns.append(card)
		_class_cards.append({"name": nm, "art": art, "weapons": wl, "note": nt})
	_note = _label("", 13, DIM)
	_note.visible = false
	page.add_child(_note)
	return page

func _refresh_class_cards() -> void:
	var all: Array = CqbMatch.kit_classes()
	for i in mini(all.size(), _class_cards.size()):
		var c: Dictionary = all[i]
		var d: Dictionary = _class_cards[i]
		(d["name"] as Label).text = String(c["name"])
		(d["art"] as WeaponArt).ids = [String(c["primary"]), String(c["second"])]
		(d["art"] as WeaponArt).queue_redraw()
		(d["weapons"] as Label).text = "%s  +  %s" % [String(Firearm.spec(String(c["primary"]))["name"]),
			String(Firearm.spec(String(c["second"]))["name"])]
		(d["note"] as Label).text = String(c.get("note", ""))
		var on: bool = i == CqbMatch.class_pick
		var b: Button = _class_btns[i]
		b.button_pressed = on
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(st, _box(CARD_HI if on else CARD,
				GOOD if on else EDGE, 8, 2 if on else 1))

# ---------------------------------------------------------- page: GUNSMITH
func _build_gunsmith_page() -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	# the left: the class's name and its two weapons
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	page.add_child(left)
	left.add_child(_label("CLASS NAME", 12, DIM))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 18
	_name_edit.add_theme_font_size_override("font_size", 16)
	_name_edit.text_changed.connect(_renamed)
	left.add_child(_name_edit)
	left.add_child(_label("WEAPONS", 12, DIM))
	_primary = _choice(left, "PRIMARY", LONG)
	_second = _choice(left, "SECOND", SECOND)
	left.add_child(_label("ON THE BENCH", 12, DIM))
	var bench := HBoxContainer.new()
	bench.add_theme_constant_override("separation", 6)
	left.add_child(bench)
	for bi in 2:
		var bb := Button.new()
		bb.custom_minimum_size = Vector2(145, 34)
		bb.add_theme_font_size_override("font_size", 12)
		bb.clip_text = true
		bb.pressed.connect(_to_bench.bind(bi))
		bench.add_child(bb)
		_bench_btns.append(bb)
	# the middle: the weapon on a turning stand, and what it does
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	page.add_child(mid)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(Color(0.02, 0.03, 0.04), EDGE, 8, 1))
	frame.custom_minimum_size = Vector2(0, 230)
	mid.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	frame.add_child(svc)
	_stand = SubViewport.new()
	_stand.own_world_3d = true
	_stand.transparent_bg = true
	_stand.size = Vector2i(560, 230)
	svc.add_child(_stand)
	_build_stand()
	for k in ["DAMAGE", "RATE", "RECOIL", "MAGNIFY", "PENETRATE", "CAPACITY"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		mid.add_child(row)
		var l := _label(k, 12, DIM)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		var bar := StatBar.new()
		bar.custom_minimum_size = Vector2(0, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var v := _label("", 12, TEXT)
		v.custom_minimum_size = Vector2(70, 0)
		row.add_child(v)
		_bars[k] = [bar, v]
	_stats = _label("", 12, DIM)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_stats)
	# the right: what is fitted
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_constant_override("separation", 8)
	page.add_child(right)
	right.add_child(_label("FITTED", 12, DIM))
	_sight = _choice(right, "SIGHT", [], false)
	for sgt in Firearm.SIGHTS:
		_sight.add_item(String(Firearm.SIGHT_NAMES[sgt]))
	_quiet = _tick(right, "Suppressor — quiet, no flash, a little slower")
	_grip = _tick(right, "Foregrip — less climb, less wander")
	_mag = _tick(right, "Extended magazine — half as many again, slower to change")
	_choke = _choice(right, "MUZZLE", [], false)
	for ck in Firearm.CHOKES:
		_choke.add_item(String(Firearm.CHOKE_NAMES[ck]))
	_slug = _tick(right, "Slugs — one heavy round, no spread, hits very hard")
	return page

## A stand for the weapon on the bench: lit, turning, against nothing.
func _build_stand() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.10, 1.25)
	cam.fov = 40.0
	cam.current = true
	_stand.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	key.light_energy = 2.6
	_stand.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -140.0, 0.0)
	fill.light_energy = 1.2
	fill.light_color = Color(0.6, 0.8, 1.0)
	_stand.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_energy = 1.4
	env.environment = e
	_stand.add_child(env)
	_stand_pivot = Node3D.new()
	_stand.add_child(_stand_pivot)

func _process(delta: float) -> void:
	# turning slowly, a little either way of side on, so it can be seen
	if visible and _page == 1 and is_instance_valid(_stand_pivot):
		_turn_t += delta
		_stand_pivot.rotation.y = sin(_turn_t * 0.5) * 0.6

func _show_on_stand(g: Dictionary, quiet: bool) -> void:
	if not is_instance_valid(_stand_pivot):
		return
	if is_instance_valid(_stand_gun):
		_stand_gun.queue_free()
	_stand_gun = Firearm.build(g, quiet)
	if _stand_gun == null:
		return
	_stand_pivot.add_child(_stand_gun)
	# Side on, and centred on its length. A weapon is built muzzle down -z,
	# which is straight at the camera: it was on the stand end-on, a dot.
	# Turned a quarter, the muzzle is to the left and the butt to the right;
	# the length runs from -len to the back of the stock.
	var front: float = float(g.get("len", 0.5)) + 0.02
	var back: float = 0.09 + float(g.get("stock", 0.0))
	_stand_gun.rotation = Vector3(0.0, PI * 0.5, 0.0)
	_stand_gun.position = Vector3((front - back) * 0.5, 0.0, 0.0)
	var span: float = front + back
	_stand_pivot.scale = Vector3.ONE * clampf(0.85 / maxf(span, 0.15), 0.8, 4.0)
	_stand_pivot.rotation = Vector3(0.0, 0.35, 0.0)

# ------------------------------------------------------- page: KILLSTREAKS
func _build_streak_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.add_child(_label("Carry up to %d. They are earned by kills without dying, cheapest first, and spent with 4 to 7." \
		% Killstreaks.MAX_STREAKS, 13, DIM))
	_streak_note = _label("", 13, ACCENT)
	page.add_child(_streak_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var pool: Array = Killstreaks.STREAK_POOL.duplicate()
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	for k in pool:
		var id := String(k["id"])
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(250, 138)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = String(k["note"])
		card.gui_input.connect(_card_clicked.bind(id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		var icon := StreakIcon.new()
		icon.id = id
		icon.custom_minimum_size = Vector2(64, 64)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var nm := _label(String(k["name"]), 14, TEXT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
		var cost := _label("%d KILLS" % int(k["at"]), 12, ACCENT)
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(cost)
		var nt := _label(String(k["note"]), 11, DIM)
		nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nt.custom_minimum_size = Vector2(150, 0)
		nt.max_lines_visible = 4
		nt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nt)
		var t := CheckButton.new()
		t.text = "CARRY"
		t.add_theme_font_size_override("font_size", 11)
		t.toggled.connect(_streak_toggled.bind(id))
		col.add_child(t)
		grid.add_child(card)
		_streak_ticks[id] = t
		_streak_cards[id] = [card, icon]
	return page

func _card_clicked(e: InputEvent, id: String) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var t: CheckButton = _streak_ticks[id]
		t.button_pressed = not t.button_pressed

# ---------------------------------------------------------- page: VEHICLE
func _build_vehicle_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.add_child(_label("Go in on foot as the class, or bring something in.", 13, DIM))
	_rides = ItemList.new()
	_rides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rides.add_theme_font_size_override("font_size", 15)
	_rides.item_selected.connect(func(_i: int): _refresh_summary())
	page.add_child(_rides)
	_ride_box = page
	return page

# -------------------------------------------------------------- the pieces
func _box(bg: Color, edge: Color, radius: int, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _label(t: String, points: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", points)
	l.add_theme_color_override("font_color", col)
	return l

func _head(t: String, points: int) -> Label:
	return _label(t, points, ACCENT)

func _choice(into: Control, label: String, ids: Array, weapon := true) -> OptionButton:
	var row := HBoxContainer.new()
	into.add_child(row)
	var l := _label(label, 12, DIM)
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(210, 32)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in ids:
		ob.add_item(String(Firearm.spec(String(id))["name"]))
	if weapon:
		ob.item_selected.connect(func(_i: int): _weapon_changed())
	else:
		ob.item_selected.connect(func(_i: int): _changed())
	row.add_child(ob)
	return ob

func _tick(into: Control, label: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.add_theme_font_size_override("font_size", 12)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.custom_minimum_size = Vector2(280, 0)
	c.toggled.connect(func(_on: bool): _changed())
	into.add_child(c)
	return c

func _show_page(i: int) -> void:
	_page = i
	for k in _pages.size():
		(_pages[k] as Control).visible = k == i
	for k in _tabs.size():
		var b: Button = _tabs[k]
		var on: bool = k == i
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, _box(CARD_HI if on else CARD,
				ACCENT if on else EDGE, 6, 2 if on else 1))
		b.add_theme_color_override("font_color", ACCENT if on else DIM)

# ------------------------------------------------------------------ open
## Show it. `takes` is what the mode lets you bring ("none", "ground", "any")
## and `first` is whether the match has not started yet -- the only time
## changing aeroplane costs nothing.
var _side_row: HBoxContainer = null
var _side_btns: Array = []

## Show the side picker: `mine` is the side this player is on, `counts` how
## many are on each. Hidden with `mine` below 0.
func show_sides(mine: int, counts: Array) -> void:
	if _side_row == null:
		return
	_side_row.visible = mine >= 0
	for i in _side_btns.size():
		var b := _side_btns[i] as Button
		b.text = "%s   %d player%s" % ["BLUE" if i == 0 else "RED", int(counts[i]),
			"" if int(counts[i]) == 1 else "s"]
		b.button_pressed = i == mine
		b.modulate = Color(0.55, 0.75, 1.0) if i == 0 else Color(1.0, 0.6, 0.55)

func _pick_side(sd: int) -> void:
	for i in _side_btns.size():
		(_side_btns[i] as Button).button_pressed = i == sd
	side_picked.emit(sd)

func open(takes: String, first: bool, faction: String, points := -1) -> void:
	_rides.clear()
	_ride_ids.clear()
	_points = points
	_add_ride("foot", "ON FOOT — as the class")
	if takes == "ground" or takes == "any":
		# Every tank, fighting vehicle, gun carrier and scout car there is,
		# his own country's first.
		var mine: Array = []
		var theirs: Array = []
		for k in VehicleSpec.KINDS:
			var kd: Dictionary = VehicleSpec.KINDS[k]
			if String(kd.get("class", "")) in ["tel", "asat", "sam", "mlrs", "spg"]:
				continue            # nothing that fights from twenty kilometres away
			if String(kd.get("faction", "")) == faction:
				mine.append(k)
			else:
				theirs.append(k)
		var order := ["mbt", "ifv", "spaag", "lav"]
		var by_class := func(x, y) -> bool:
			return order.find(String(VehicleSpec.KINDS[x].get("class", ""))) \
				< order.find(String(VehicleSpec.KINDS[y].get("class", "")))
		mine.sort_custom(by_class)
		theirs.sort_custom(by_class)
		var tags := {"mbt": "tank", "ifv": "fighting vehicle", "spaag": "anti-air gun", "lav": "scout car"}
		for k in mine + theirs:
			var kd2: Dictionary = VehicleSpec.KINDS[k]
			_add_ride("veh:" + String(k), "%s — %s" % [String(kd2["name"]),
				String(tags.get(String(kd2.get("class", "")), ""))])
	# In the air from the start if it was chosen before the match; earned with
	# points once it has begun (see `Killstreaks.ride_cost`).
	if takes == "any" and (first or points >= 0):
		for id in JetSpec.ids_for(faction):
			var sp0 := JetSpec.get_spec(id)
			if bool(sp0.get("unmanned", false)) or bool(sp0.get("gunship", false)):
				continue
			var sp := JetSpec.get_spec(id)
			_add_ride(String(id), "%s — %s" % [String(sp["name"]), String(sp["role"])])
	# nothing to choose but walking: no page for it
	(_tabs[3] as Button).visible = _ride_ids.size() > 1
	_rides.select(0)
	_pick(CqbMatch.class_pick)
	_show_streaks()
	_show_page(0)
	# for a harness that wants a picture of one page or another
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--deploypage="):
			_show_page(clampi(int(a.substr(13)), 0, _pages.size() - 1))
	visible = true

## Points to spend, or -1 when nothing costs anything.
var _points := -1

func _add_ride(id: String, text: String) -> void:
	var cost: int = Killstreaks.ride_cost(id) if _points >= 0 else 0
	if cost > 0:
		text += "   [%d pts]" % cost
	_rides.add_item(text)
	_ride_ids.append(id)
	if cost > _points and _points >= 0:
		# earned with kills: shown, so there is something to work toward
		_rides.set_item_disabled(_rides.item_count - 1, true)
		_rides.set_item_custom_fg_color(_rides.item_count - 1, DIM)

# ------------------------------------------------------------------ class
func _pick(i: int) -> void:
	var all: Array = CqbMatch.kit_classes()
	CqbMatch.class_pick = clampi(i, 0, all.size() - 1)
	var c: Dictionary = all[CqbMatch.class_pick]
	_filling = true
	_primary.select(maxi(LONG.find(String(c["primary"])), 0))
	_second.select(maxi(SECOND.find(String(c["second"])), 0))
	_name_edit.text = String(c["name"])
	_filling = false
	_note.text = String(c.get("note", ""))
	_refresh_class_cards()
	_to_bench(_bench)

func _renamed(t: String) -> void:
	if _filling:
		return
	var c: Dictionary = CqbMatch.kit_classes()[CqbMatch.class_pick]
	c["name"] = t.strip_edges().to_upper() if t.strip_edges() != "" else String(c["name"])
	_refresh_class_cards()
	_refresh_summary()

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
		var on: bool = k == _bench
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, _box(CARD_HI if on else CARD, GOOD if on else EDGE, 6, 2 if on else 1))
	var id: String = _bench_id(c)
	var g: Dictionary = Firearm.spec(id)
	var s: Dictionary = Firearm.setup_for(c, id)
	var bare: bool = g.has("launcher") or bool(g.get("hand", false))
	_filling = true
	_sight.select(maxi(Firearm.SIGHTS.find(String(s["sight"])), 0))
	_quiet.button_pressed = bool(s["quiet"]) and Firearm.can_suppress(g)
	_grip.button_pressed = bool(s["grip"]) and not bare
	_mag.button_pressed = bool(s["mag"]) and not bare
	var shot: bool = Firearm.is_shotgun(g)
	_choke.select(maxi(Firearm.CHOKES.find(String(s.get("choke", "none"))), 0) if shot else 0)
	_slug.button_pressed = bool(s.get("slug", false)) and shot
	_filling = false
	_sight.disabled = bare
	_quiet.disabled = not Firearm.can_suppress(g)
	_grip.disabled = bare
	_mag.disabled = bare
	_choke.disabled = not shot
	_slug.disabled = not shot
	_show_stats(c)

## A different weapon was chosen for one of the two slots.
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
	_refresh_class_cards()
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
	if not _choke.disabled:
		s["choke"] = Firearm.CHOKES[_choke.selected]
		s["slug"] = _slug.button_pressed
	_show_stats(c)

## One weapon as it is fitted, in words.
func _stat_lines(c: Dictionary, id: String) -> String:
	var base: Dictionary = Firearm.spec(id)
	var launcher: String = String(base.get("launcher", ""))
	if launcher == "rocket":
		return "%s — three rockets: armour, walls, anything" % String(base["name"])
	if launcher == "sam":
		return "%s — two missiles: aircraft only, needs a lock" % String(base["name"])
	if launcher == "gl":
		return "%s — six 40 mm rounds in the drum, twelve more: they arc, and burst past ten metres" \
			% String(base["name"])
	var g: Dictionary = Firearm.fitted(id, Firearm.setup_for(c, id))
	var pen: float = Firearm.pen_of(g)
	return "%s — %s; goes through %s. Fire select: %s." % [
		String(g["name"]),
		"heard at 14 m" if bool(g.get("quiet", false)) else "heard at 75 m",
		"walls, cars and several men" if pen >= 1.0
		else ("a house wall, or two men" if pen >= 0.6
		else ("a thin wall or a fence, or one man" if pen >= 0.3
		else "planks and not much else")),
		" / ".join(PackedStringArray(Walker.modes_of(g))).to_upper()]

func _show_stats(c: Dictionary) -> void:
	var id: String = _bench_id(c)
	var base: Dictionary = Firearm.spec(id)
	var setup: Dictionary = Firearm.setup_for(c, id)
	var g: Dictionary = Firearm.fitted(id, setup) if not base.has("launcher") else base
	_stats.text = "%s\n\n%s" % [_stat_lines(c, String(c["primary"])), _stat_lines(c, String(c["second"]))]
	_show_on_stand(g, bool(setup.get("quiet", false)) and Firearm.can_suppress(base))
	# the bars, against the hardest hitter, the fastest and so on in the kit
	var dmg: float = float(g.get("dmg", 0.0)) * float(g.get("pellets", 1))
	var rate: float = 60.0 / maxf(float(g.get("cd", 1.0)), 0.01)
	var rec: float = float(g.get("kick", 0.0))
	var mag: float = 74.0 / maxf(float(g.get("fov", 74.0)), 1.0)
	var pen: float = Firearm.pen_of(g) if not base.has("launcher") else 1.2
	var cap: float = float(g.get("mag", 0))
	_bar("DAMAGE", dmg / 160.0, "%d" % int(dmg))
	_bar("RATE", rate / 1300.0, "%d rpm" % int(rate))
	_bar("RECOIL", rec / 0.06, "%d" % int(rec * 1000.0))
	_bar("MAGNIFY", (mag - 1.0) / 6.0, "%.1fx" % mag)
	_bar("PENETRATE", pen / 1.2, "%.1f" % pen)
	_bar("CAPACITY", cap / 100.0, "%d" % int(cap))
	_refresh_summary()

func _bar(k: String, v: float, txt: String) -> void:
	if not _bars.has(k):
		return
	var bar: StatBar = _bars[k][0]
	bar.value = clampf(v, 0.02, 1.0)
	bar.queue_redraw()
	(_bars[k][1] as Label).text = txt

# ------------------------------------------------------------- killstreaks
## One ticked or unticked. A fifth is refused rather than quietly dropping
## one of the others, and the last one cannot be taken off.
func _streak_toggled(on: bool, id: String) -> void:
	if _filling:
		return
	var pick: Array = Killstreaks.streak_pick
	if on and not pick.has(id):
		if pick.size() >= Killstreaks.MAX_STREAKS:
			_filling = true
			(_streak_ticks[id] as CheckButton).button_pressed = false
			_filling = false
			_streak_note.text = "Four at most: take one off first."
			return
		pick.append(id)
	elif not on and pick.has(id):
		if pick.size() <= 1:
			_filling = true
			(_streak_ticks[id] as CheckButton).button_pressed = true
			_filling = false
			_streak_note.text = "Carry at least one."
			return
		pick.erase(id)
	_show_streaks()

func _show_streaks() -> void:
	_filling = true
	for id in _streak_ticks:
		var on: bool = Killstreaks.streak_pick.has(id)
		(_streak_ticks[id] as CheckButton).button_pressed = on
		var card: PanelContainer = _streak_cards[id][0]
		card.add_theme_stylebox_override("panel", _box(CARD_HI if on else CARD, GOOD if on else EDGE, 8, 2 if on else 1))
		var icon: StreakIcon = _streak_cards[id][1]
		icon.lit = on
		icon.queue_redraw()
	_filling = false
	var keys := PackedStringArray()
	for k in Killstreaks.chosen_streaks():
		keys.append("%d  %s" % [int(k["key"]), String(k["name"])])
	_streak_note.text = "Carried:   " + "      ".join(keys)
	_refresh_summary()

# ------------------------------------------------------------------ bottom
func _refresh_summary() -> void:
	if _sum_class == null:
		return
	var all: Array = CqbMatch.kit_classes()
	var c: Dictionary = all[clampi(CqbMatch.class_pick, 0, all.size() - 1)]
	var picked: PackedInt32Array = _rides.get_selected_items() if _rides != null else PackedInt32Array()
	var ride: String = "" if picked.is_empty() or picked[0] == 0 else \
		"   in a " + _rides.get_item_text(picked[0]).get_slice(" — ", 0)
	_sum_class.text = String(c["name"]) + ride
	_sum_weapons.text = "%s   +   %s" % [String(Firearm.spec(String(c["primary"]))["name"]),
		String(Firearm.spec(String(c["second"]))["name"])]
	for ch in _sum_streaks.get_children():
		ch.queue_free()
	for k in Killstreaks.chosen_streaks():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		var ic := StreakIcon.new()
		ic.id = String(k["id"])
		ic.lit = true
		ic.custom_minimum_size = Vector2(40, 40)
		ic.tooltip_text = "%s — %d kills" % [String(k["name"]), int(k["at"])]
		box.add_child(ic)
		var kl := _label("%d" % int(k["key"]), 11, DIM)
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(kl)
		_sum_streaks.add_child(box)

func _go() -> void:
	var picked: PackedInt32Array = _rides.get_selected_items()
	var id: String = "foot" if picked.is_empty() else String(_ride_ids[picked[0]])
	visible = false
	deploy.emit(id)

# ---------------------------------------------------------------- drawings
## A bar from nothing to full.
class StatBar extends Control:
	var value := 0.0
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.10, 0.13, 0.16))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), Color(0.38, 0.86, 1.0, 0.85))
		for i in range(1, 10):
			var x: float = size.x * float(i) / 10.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.35), 1.0)

## The two weapons of a class, drawn side on in outline.
class WeaponArt extends Control:
	var ids: Array = []
	func _draw() -> void:
		var x := 0.0
		for i in ids.size():
			var w: float = size.x * (0.6 if i == 0 else 0.36)
			_gun(String(ids[i]), Rect2(x, 0.0, w, size.y), Color(0.75, 0.88, 0.96) if i == 0 else Color(0.55, 0.65, 0.72))
			x += w + size.x * 0.04
	func _gun(id: String, r: Rect2, col: Color) -> void:
		var g: Dictionary = Firearm.spec(id)
		var y: float = r.position.y + r.size.y * 0.45
		var lng: float = r.size.x
		var h: float = r.size.y * 0.16
		if g.has("launcher"):
			draw_rect(Rect2(r.position.x, y - h * 0.9, lng * 0.95, h * 1.8), col)
			draw_rect(Rect2(r.position.x + lng * 0.45, y + h * 0.9, lng * 0.06, h * 1.4), col)
			return
		var hand: bool = bool(g.get("hand", false))
		var stock: float = 0.0 if hand else lng * 0.22
		var body: float = lng * (0.4 if hand else 0.32)
		var barrel: float = lng - stock - body
		var x0: float = r.position.x
		# stock, receiver, barrel
		if stock > 0.0:
			draw_colored_polygon(PackedVector2Array([Vector2(x0, y - h * 0.5), Vector2(x0 + stock, y - h * 0.8),
				Vector2(x0 + stock, y + h * 0.8), Vector2(x0, y + h * 1.6)]), col)
		draw_rect(Rect2(x0 + stock, y - h, body, h * 2.0), col)
		draw_rect(Rect2(x0 + stock + body, y - h * 0.35, barrel, h * 0.7), col)
		# grip and magazine
		draw_rect(Rect2(x0 + stock + body * 0.15, y + h, body * 0.16, h * 2.0), col)
		if int(g.get("mag", 0)) > 1 and not bool(g.get("shells", false)):
			draw_rect(Rect2(x0 + stock + body * 0.5, y + h, body * 0.2, h * (2.6 if not g.get("box", false) else 2.0)), col)
		# a scope or a dot on top
		if bool(g.get("scope", false)):
			draw_rect(Rect2(x0 + stock + body * 0.2, y - h * 2.2, body * 0.7, h * 0.9), col)
		elif bool(g.get("dot", false)):
			draw_rect(Rect2(x0 + stock + body * 0.45, y - h * 1.8, body * 0.18, h * 0.8), col)

## A killstreak's mark: a small drawing of what it is.
class StreakIcon extends Control:
	var id := ""
	var lit := false
	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var c: Vector2 = size * 0.5
		var col := Color(0.50, 1.0, 0.70) if lit else Color(0.56, 0.66, 0.74)
		draw_circle(c, s * 0.48, Color(0.04, 0.06, 0.08))
		draw_arc(c, s * 0.48, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.8), 2.0)
		var u: float = s * 0.30
		match id:
			"uav":
				_plane(c, u, col, 0.0, true)
				draw_arc(c + Vector2(0, u * 0.9), u * 0.5, PI * 1.15, PI * 1.85, 10, col, 1.5)
			"cuav":
				_plane(c, u * 0.8, col, 0.0, true)
				draw_line(c + Vector2(-u, -u), c + Vector2(u, u), Color(1.0, 0.4, 0.3), 2.5)
			"smoke":
				for k in 4:
					draw_circle(c + Vector2((float(k) - 1.5) * u * 0.55, u * 0.15 - sin(float(k)) * u * 0.25),
						u * 0.42, col)
			"supply", "vest":
				draw_rect(Rect2(c - Vector2(u * 0.75, u * 0.25), Vector2(u * 1.5, u)), col, false, 2.0)
				draw_line(c + Vector2(-u * 0.75, u * 0.25), c + Vector2(u * 0.75, u * 0.25), col, 2.0)
				draw_arc(c - Vector2(0, u * 0.55), u * 0.6, PI, TAU, 14, col, 1.5)
				if id == "vest":
					draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.3, u * 0.35), c + Vector2(u * 0.3, u * 0.35),
						c + Vector2(u * 0.22, u * 0.7), c + Vector2(-u * 0.22, u * 0.7)]), col)
			"mortar", "missile":
				for k in 3:
					var p: Vector2 = c + Vector2((float(k) - 1.0) * u * 0.6, -u * 0.2)
					draw_line(p + Vector2(0, -u * 0.5), p + Vector2(0, u * 0.6), col, 2.5)
					draw_colored_polygon(PackedVector2Array([p + Vector2(-u * 0.12, -u * 0.5),
						p + Vector2(u * 0.12, -u * 0.5), p + Vector2(0, -u * 0.8)]), col)
			"sentry":
				draw_line(c + Vector2(0, -u * 0.2), c + Vector2(-u * 0.6, u * 0.8), col, 2.0)
				draw_line(c + Vector2(0, -u * 0.2), c + Vector2(u * 0.6, u * 0.8), col, 2.0)
				draw_line(c + Vector2(0, -u * 0.2), c + Vector2(0, u * 0.8), col, 2.0)
				draw_rect(Rect2(c + Vector2(-u * 0.4, -u * 0.55), Vector2(u * 0.6, u * 0.4)), col)
				draw_line(c + Vector2(u * 0.2, -u * 0.38), c + Vector2(u * 1.0, -u * 0.38), col, 3.0)
			"strike", "carpet", "wp":
				_plane(c - Vector2(0, u * 0.3), u * 0.9, col, 0.0, false)
				for k in 3:
					draw_circle(c + Vector2((float(k) - 1.0) * u * 0.45, u * 0.55 + float(k) * u * 0.1), u * 0.12,
						Color(1.0, 0.55, 0.2) if id == "wp" else col)
			"strafe":
				_plane(c - Vector2(u * 0.2, u * 0.3), u * 0.9, col, 0.0, false)
				for k in 4:
					var q: Vector2 = c + Vector2(-u * 0.6 + float(k) * u * 0.4, u * 0.7)
					draw_line(q, q + Vector2(u * 0.1, -u * 0.2), col, 2.0)
			"dogs":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-u, 0), c + Vector2(u * 0.4, -u * 0.1),
					c + Vector2(u * 0.6, -u * 0.6), c + Vector2(u, -u * 0.4), c + Vector2(u * 0.7, u * 0.1),
					c + Vector2(u * 0.5, u * 0.7), c + Vector2(u * 0.3, u * 0.7), c + Vector2(u * 0.2, u * 0.2),
					c + Vector2(-u * 0.5, u * 0.2), c + Vector2(-u * 0.6, u * 0.7), c + Vector2(-u * 0.8, u * 0.7),
					c + Vector2(-u * 0.8, u * 0.1)]), col)
			"swarm":
				for k in 4:
					var a: float = TAU * float(k) / 4.0 + 0.4
					_plane(c + Vector2(cos(a), sin(a)) * u * 0.55, u * 0.35, col, a, true)
			"heli", "chopper":
				draw_line(c + Vector2(-u * 1.1, -u * 0.55), c + Vector2(u * 1.1, -u * 0.55), col, 2.0)
				draw_line(c + Vector2(0, -u * 0.55), c + Vector2(0, -u * 0.25), col, 2.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.6, -u * 0.25), c + Vector2(u * 0.3, -u * 0.25),
					c + Vector2(u * 0.55, u * 0.15), c + Vector2(u * 0.2, u * 0.35), c + Vector2(-u * 0.6, u * 0.3)]), col)
				draw_line(c + Vector2(-u * 0.6, 0), c + Vector2(-u * 1.1, -u * 0.1), col, 2.5)
				if id == "chopper":
					draw_line(c + Vector2(u * 0.4, u * 0.25), c + Vector2(u * 0.9, u * 0.75), Color(1.0, 0.86, 0.4), 2.0)
			"gunship":
				_plane(c, u, col, 0.0, false)
				draw_line(c + Vector2(-u * 0.2, u * 0.1), c + Vector2(-u * 0.9, u * 0.9), Color(1.0, 0.86, 0.4), 2.0)
			"cruise":
				draw_line(c + Vector2(-u, u * 0.5), c + Vector2(u, -u * 0.5), col, 4.0)
				draw_line(c + Vector2(-u * 0.2, u * 0.1), c + Vector2(-u * 0.5, -u * 0.35), col, 2.0)
			"armour":
				draw_rect(Rect2(c + Vector2(-u * 0.9, 0), Vector2(u * 1.8, u * 0.55)), col)
				draw_rect(Rect2(c + Vector2(-u * 0.4, -u * 0.35), Vector2(u * 0.8, u * 0.4)), col)
				draw_line(c + Vector2(u * 0.3, -u * 0.18), c + Vector2(u * 1.1, -u * 0.3), col, 3.0)
				draw_arc(c - Vector2(0, u * 0.9), u * 0.6, PI, TAU, 14, col, 1.5)
			"jugg":
				draw_circle(c - Vector2(0, u * 0.45), u * 0.38, col)
				draw_rect(Rect2(c + Vector2(-u * 0.6, -u * 0.05), Vector2(u * 1.2, u * 0.95)), col)
				draw_rect(Rect2(c + Vector2(-u * 0.25, -u * 0.6), Vector2(u * 0.5, u * 0.12)), Color(0.04, 0.06, 0.08))
			"emp":
				draw_colored_polygon(PackedVector2Array([c + Vector2(u * 0.15, -u), c + Vector2(-u * 0.5, u * 0.1),
					c + Vector2(0, u * 0.1), c + Vector2(-u * 0.15, u), c + Vector2(u * 0.5, -u * 0.1),
					c + Vector2(0, -u * 0.1)]), Color(0.6, 0.85, 1.0))
			"tacnuke", "stratnuke":
				draw_circle(c, u * 0.25, col)
				for k in 3:
					var a2: float = TAU * float(k) / 3.0 - PI * 0.5
					draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a2 - 0.5), sin(a2 - 0.5)) * u * 0.4,
						c + Vector2(cos(a2 - 0.5), sin(a2 - 0.5)) * u, c + Vector2(cos(a2 + 0.5), sin(a2 + 0.5)) * u,
						c + Vector2(cos(a2 + 0.5), sin(a2 + 0.5)) * u * 0.4]),
						Color(1.0, 0.35, 0.25) if id == "stratnuke" else Color(1.0, 0.75, 0.25))
			_:
				draw_circle(c, u * 0.4, col)
	## A small aeroplane from above, nose up the icon: delta for a drone.
	func _plane(c: Vector2, u: float, col: Color, turn: float, drone: bool) -> void:
		var pts := PackedVector2Array()
		if drone:
			pts = PackedVector2Array([Vector2(0, -u), Vector2(u, u * 0.5), Vector2(0, u * 0.2), Vector2(-u, u * 0.5)])
		else:
			pts = PackedVector2Array([Vector2(0, -u), Vector2(u * 0.12, -u * 0.3), Vector2(u, 0),
				Vector2(u * 0.12, u * 0.1), Vector2(u * 0.08, u * 0.6), Vector2(u * 0.4, u * 0.85),
				Vector2(-u * 0.4, u * 0.85), Vector2(-u * 0.08, u * 0.6), Vector2(-u * 0.12, u * 0.1),
				Vector2(-u, 0), Vector2(-u * 0.12, -u * 0.3)])
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p.rotated(turn))
		draw_colored_polygon(out, col)
