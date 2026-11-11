class_name Menu
extends Control
## Hangar screen: pick an airframe, pick what to fly, launch.

signal jet_changed(id: String)
signal start_requested(id: String, mission: String)
signal mission_changed(mission: String)
signal weather_changed(id: String)
signal host_requested(id: String, address: String)
signal join_requested(id: String, address: String)
signal resume_requested()
signal settings_requested()

const MISSIONS := [
	["takeoff", "RUNWAY START", "No threats. Cold on runway 36 — firewall it, rotate around 150 kt, gear up with G."],
	["free", "FREE FLIGHT", "No threats. Airborne over the valley with a full tank. Roam, then come back and land."],
	["landing", "APPROACH", "No threats. Twelve km final at 3000 ft — fly the PAPI down and grease it on."],
	["ramp", "RAMP WALK", "No threats. Start on foot beside the flight line — walk over and press E to climb into any jet."],
	["sandbox", "SANDBOX", "Everything at once. The vehicle park, the flight line, hostile aircraft and the satellites, with nothing trying to score. Somewhere to try things out."],
	["conquest", "CONQUEST", "Hostile. Five sectors across the valley — hold more than they do and their tickets bleed away."],
	["rush", "RUSH", "Hostile. Sectors open one at a time; smash the garrison or hold the ring to advance."],
	["warlords", "WARLORDS", "Hostile. Sequential sectors that pay command points as you take them."],
	["cqb", "CQB", "Hostile, and on foot. Two squads in the streets of a town, as many a side as you choose — no vehicles, no air. Rifles, corners and whatever is lying in the road to get behind. First side to the kills you set."],
	["ground", "GROUND COMBAT", "Hostile. The same streets with armour in them: two squads and two vehicles a side. Take a tank, a fighting vehicle or anything else off the ground list — or go on foot and stay out of their way. First side to the kills you set."],
	["arms", "COMBAT", "Hostile. Everything over one town: infantry in the streets, armour among them and both sides' aircraft overhead. Take an aeroplane, a helicopter, a vehicle, or go on foot. First side to the kills you set."],
	["tdm", "TEAM DEATHMATCH", "Hostile. Two sides, first to twenty kills."],
	["ffa", "FREE FOR ALL", "Hostile. Everyone shoots everyone; twelve kills wins."],
	["carrier", "CARRIER TRAP", "No threats. Three miles behind the boat with the hook down."],
	["strike", "STRIKE", "No air threat. Armour columns, shipping and helicopters to hunt, wave after wave — nothing down there can shoot back at an aeroplane."],
	["combat", "PATROL", "Hostile. Bandits and a SAM belt north of the field. Open the bay before you shoot."],
]

var jet_id := "f22"
var mission_id := "takeoff"
var paused := false
var _cards := {}
var _faction_btns := {}
var _grid: GridContainer
var faction := ""
var _mission_btns := {}
var _weather_btns := {}
var _stats: VBoxContainer
var _blurb: Label
var _launch: Button
var _resume: Button
var _panel: ColorRect
var _addr: LineEdit
var _net_status: Label
var _root: VBoxContainer

func _ready() -> void:
	# A Control parented straight to a CanvasLayer does not inherit a size, so the
	# anchors have nothing to resolve against: pin it to the viewport by hand.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.08, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var panel := ColorRect.new()
	panel.color = Color(0.04, 0.06, 0.09, 0.88)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 760.0
	_panel = panel
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var root := VBoxContainer.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_top = 42
	root.offset_right = -600
	root.offset_bottom = -42
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var title := Label.new()
	title.text = "COMBINED ARMS"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "pick the mode first — it decides what you can take into it"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	root.add_child(sub)

	# Everything you browse goes in a scroll view; the launch bar and the help
	# line stay pinned below it. With twenty odd airframes plus the ground fleet
	# the list can outgrow the window, and the start button must never be the
	# thing that falls off the bottom.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)

	# The mode comes first. What you can take depends on it -- nothing at all
	# into a street fight, anything on wheels or tracks into a ground battle --
	# so choosing the vehicle first meant choosing something the mode then
	# quietly ignored.
	_mode_box = VBoxContainer.new()
	_mode_box.add_theme_constant_override("separation", 8)
	inner.add_child(_mode_box)
	var h1 := Label.new()
	h1.text = "1   MODE"
	h1.add_theme_font_size_override("font_size", 14)
	h1.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	_mode_box.add_child(h1)
	_veh_head = Label.new()
	_veh_head.text = "2   WHAT YOU TAKE"
	_veh_head.add_theme_font_size_override("font_size", 14)
	_veh_head.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	inner.add_child(_veh_head)
	var frow := HBoxContainer.new()
	_frow = frow
	frow.add_theme_constant_override("separation", 6)
	inner.add_child(frow)
	var facs := [["", "ALL"], ["ground", "GROUND"], ["sea", "NAVAL"]]
	for f in JetSpec.FACTIONS:
		facs.append([f, str(JetSpec.FACTIONS[f]["name"]).split(" ")[0]])
	for f in facs:
		var fb := Button.new()
		fb.custom_minimum_size = Vector2(96, 30)
		fb.text = str(f[1])
		fb.add_theme_font_size_override("font_size", 12)
		fb.pressed.connect(_select_faction.bind(str(f[0])))
		frow.add_child(fb)
		_faction_btns[str(f[0])] = fb

	var row := GridContainer.new()
	row.columns = 6
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	inner.add_child(row)
	_grid = row
	_rebuild_cards()

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 18)
	inner.add_child(mid)

	_stats = VBoxContainer.new()
	_stats.custom_minimum_size = Vector2(360, 0)
	_stats.add_theme_constant_override("separation", 3)
	mid.add_child(_stats)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	mid.add_child(right)
	_blurb = Label.new()
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.add_theme_font_size_override("font_size", 15)
	_blurb.add_theme_color_override("font_color", Color(0.78, 0.86, 0.94))
	_blurb.custom_minimum_size = Vector2(0, 96)
	right.add_child(_blurb)

	var mgrid := GridContainer.new()
	mgrid.columns = 6
	mgrid.add_theme_constant_override("h_separation", 8)
	mgrid.add_theme_constant_override("v_separation", 6)
	_mode_box.add_child(mgrid)
	var mrow := mgrid
	for m in MISSIONS:
		var mb := Button.new()
		mb.custom_minimum_size = Vector2(104, 44)
		mb.text = m[1]
		mb.add_theme_font_size_override("font_size", 13)
		mb.tooltip_text = m[2]
		mb.pressed.connect(_select_mission.bind(m[0]))
		mrow.add_child(mb)
		_mission_btns[m[0]] = mb
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	right.add_child(wrow)
	var wl := Label.new()
	wl.text = "WEATHER "
	wl.add_theme_font_size_override("font_size", 13)
	wl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	wrow.add_child(wl)
	for w in Weather.ids():
		var wb := Button.new()
		wb.custom_minimum_size = Vector2(112, 34)
		wb.text = str(Weather.PRESETS[w]["name"])
		wb.add_theme_font_size_override("font_size", 12)
		wb.pressed.connect(_select_weather.bind(w))
		wrow.add_child(wb)
		_weather_btns[w] = wb

	# Close quarters has things to choose that no other mission does: where,
	# and what to carry in. Shown only while it is the mission picked.
	_cqb_row = HBoxContainer.new()
	_cqb_row.add_theme_constant_override("separation", 8)
	_cqb_row.visible = false
	_mode_box.add_child(_cqb_row)
	_cqb_town = _cqb_pick("TOWN", [])
	_cqb_town.item_selected.connect(func(i: int): CqbMatch.town = _cqb_town.get_item_id(i))
	# how many a side: ours, the player among them, and theirs
	var sizes: Array = []
	for n in CqbMatch.SIZES:
		sizes.append("%d" % int(n))
	var us := _cqb_pick("OUR SIDE", sizes)
	var them := _cqb_pick("THEIR SIDE", sizes)
	for ob in [us, them]:
		(ob as OptionButton).custom_minimum_size = Vector2(64, 30)
	us.select(maxi(CqbMatch.SIZES.find(CqbMatch.size_us), 0))
	them.select(maxi(CqbMatch.SIZES.find(CqbMatch.size_them), 0))
	us.item_selected.connect(func(i: int): CqbMatch.size_us = int(CqbMatch.SIZES[i]))
	them.item_selected.connect(func(i: int): CqbMatch.size_them = int(CqbMatch.SIZES[i]))
	# and what it is played to
	var goals: Array = []
	for n in CqbMatch.GOALS:
		goals.append("%d" % int(n))
	var to_win := _cqb_pick("KILLS TO WIN", goals)
	to_win.custom_minimum_size = Vector2(72, 30)
	to_win.select(maxi(CqbMatch.GOALS.find(CqbMatch.kill_goal), 0))
	to_win.item_selected.connect(func(i: int): CqbMatch.kill_goal = int(CqbMatch.GOALS[i]))

	var mdesc := Label.new()
	mdesc.name = "MissionDesc"
	mdesc.add_theme_font_size_override("font_size", 14)
	mdesc.add_theme_color_override("font_color", Color(0.62, 0.72, 0.82))
	mdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_box.add_child(mdesc)
	_mode_box.move_child(mdesc, 2)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	root.add_child(btns)
	_launch = Button.new()
	_launch.text = "LAUNCH"
	_launch.custom_minimum_size = Vector2(190, 52)
	_launch.add_theme_font_size_override("font_size", 20)
	_launch.pressed.connect(func():
		var a := launch_args()
		start_requested.emit(String(a[0]), String(a[1])))
	btns.add_child(_launch)
	_resume = Button.new()
	_resume.text = "RESUME"
	_resume.custom_minimum_size = Vector2(150, 52)
	_resume.pressed.connect(func(): resume_requested.emit())
	_resume.visible = false
	btns.add_child(_resume)
	var net_row := HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 8)
	root.add_child(net_row)
	var nl := Label.new()
	nl.text = "MULTIPLAYER "
	nl.add_theme_font_size_override("font_size", 13)
	nl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	net_row.add_child(nl)
	_addr = LineEdit.new()
	_addr.text = "127.0.0.1"
	_addr.custom_minimum_size = Vector2(150, 34)
	_addr.add_theme_font_size_override("font_size", 13)
	net_row.add_child(_addr)
	var hb := Button.new()
	hb.text = "HOST"
	hb.custom_minimum_size = Vector2(110, 34)
	hb.pressed.connect(func(): host_requested.emit(jet_id, _addr.text))
	net_row.add_child(hb)
	var jb := Button.new()
	jb.text = "JOIN"
	jb.custom_minimum_size = Vector2(110, 34)
	jb.pressed.connect(func(): join_requested.emit(jet_id, _addr.text))
	net_row.add_child(jb)
	# The session line carries the address people have to type, so it is not a
	# 12pt afterthought at the end of a row — and it is selectable, because the
	# first thing anyone does with an address is copy it.
	_net_status = Label.new()
	_net_status.add_theme_font_size_override("font_size", 16)
	_net_status.add_theme_color_override("font_color", Color(0.62, 0.95, 0.75))
	_net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_status.custom_minimum_size = Vector2(520, 0)
	net_row.add_child(_net_status)

	var settings := Button.new()
	settings.text = "SETTINGS"
	settings.custom_minimum_size = Vector2(130, 52)
	settings.pressed.connect(func(): settings_requested.emit())
	btns.add_child(settings)
	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(110, 52)
	quit.pressed.connect(func(): get_tree().quit())
	btns.add_child(quit)

	var help := Label.new()
	# Read off the bindings rather than written out here. This line said TAB
	# cycled weapons, V fired the gun, N threw flares and M was the mouse stick
	# -- four keys that had all moved, on the first screen anybody sees.
	help.text = "W/S pitch  ·  A/D roll  ·  Q/E rudder  ·  SHIFT/CTRL throttle  ·  G gear  ·  F flaps  ·  X brakes\n" \
		+ "B bay doors  ·  1-8 pick weapon  ·  %s cycle  ·  %s target  ·  SPACE fire  ·  %s gun  ·  %s flares  ·  %s chaff\n" % [
			Sim.key_label(&"cycle_weapon"), Sim.key_label(&"cycle_target"),
			Sim.key_label(&"gun"), Sim.key_label(&"flare"), Sim.key_label(&"chaff")] \
		+ "%s camera (cockpit / chase / orbit)  ·  %s night vision  ·  %s mouse stick  ·  %s fly-by-wire  ·  ESC menu" % [
			Sim.key_label(&"camera"), Sim.key_label(&"night_vision"),
			Sim.key_label(&"mouse_fly"), Sim.key_label(&"assist")]
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(0.55, 0.62, 0.7))
	root.add_child(help)

	_select_faction("")
	_select(jet_id)
	_select_mission(mission_id)
	_select_weather(Sim.weather)

func _select_faction(f: String) -> void:
	faction = f
	for k in _faction_btns:
		_faction_btns[k].modulate = Color(1, 1, 1) if k != f else Color(0.55, 1.0, 0.75)
	_rebuild_cards()
	if f == "ground":
		_select("veh:" + str(Tank.KINDS.keys()[0]))
		return
	if f == "sea":
		_select("sea:" + _crewable_ships()[0])
		return
	var list := JetSpec.ids_for(faction)
	if list.size() > 0 and not list.has(jet_id):
		_select(list[0])
	else:
		_select(jet_id)

## Ships the player can crew: anything with a main mount.
## Ships the player can crew: anything with a main mount or launch tubes. Only
## the gun counted before, which left the submarine off the list entirely.
func _crewable_ships() -> Array:
	var out: Array = []
	for k in Ship.KINDS:
		var kd: Dictionary = Ship.KINDS[k]
		if int(kd["guns"]) > 0 or int(kd.get("vls", 0)) > 0:
			out.append(k)
	return out

## The stats page for anything afloat, the carrier included.
func _fill_sea(kind: String) -> void:
	for c in _stats.get_children():
		c.queue_free()
	var rows: Array = []
	if kind == "carrier":
		_blurb.text = "Fleet carrier\n\nThe aeroplanes are the armament. Four wires on an angled deck, two bow catapults, and nothing that shoots.\n\nW/S engine order, A/D helm, mouse looks out from the island, U to hand over."
		rows = [
			["ROLE", 1.0, "fleet carrier"],
			["LENGTH", clampf(Carrier.LEN / 340.0, 0.05, 1.0), "%d m" % int(Carrier.LEN)],
			["BEAM", clampf(Carrier.BEAM / 45.0, 0.05, 1.0), "%d m" % int(Carrier.BEAM)],
			["TOP SPEED", clampf(Carrier.TOP_SPEED / 20.0, 0.05, 1.0),
				"%.0f kts" % (Carrier.TOP_SPEED * 1.94384)],
			["ARRESTOR WIRES", 1.0, "%d" % Carrier.WIRES.size()],
			["ARMAMENT", 0.05, "none"],
		]
	else:
		var kd: Dictionary = Ship.KINDS[kind]
		var sub: bool = bool(kd.get("sub", false))
		_blurb.text = "%s\n\n%s\n\nW/S engine order, A/D helm, mouse lays the battery, left click fires, U to hand over." % [
			str(kd["name"]),
			"Runs deep and shoots from under the surface." if sub
			else "Surface combatant."]
		rows = [
			["ROLE", 1.0, "submarine" if sub else String(kd.get("class", "warship"))],
			["LENGTH", clampf(float(kd["len"]) / 200.0, 0.05, 1.0), "%d m" % int(kd["len"])],
			["TOP SPEED", clampf(float(kd["speed"]) / 20.0, 0.05, 1.0),
				"%.0f kts" % (float(kd["speed"]) * 1.94384)],
			["HULL", clampf(float(kd["hp"]) / 2500.0, 0.05, 1.0), "%d" % int(kd["hp"])],
			["GUNS", clampf(float(int(kd.get("guns", 0))) / 3.0, 0.02, 1.0),
				"%d" % int(kd.get("guns", 0))],
			["LAUNCH CELLS", clampf(float(int(kd.get("vls", 0))) / 40.0, 0.02, 1.0),
				"%d" % int(kd.get("vls", 0))],
		]
	for r in rows:
		_stats.add_child(_stat_row(str(r[0]), float(r[1]), str(r[2])))

func _rebuild_cards() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	# aircraft first, then everything that drives, so the ground fleet is visible
	# without having to know the GROUND tab exists
	# a ship you can take command of: the ones with a gun on the foredeck
	var takes := mode_takes(mission_id)
	if takes == "ground" or takes == "any":
		# no vehicle at all is a choice, in the modes fought over a town
		var fb := Button.new()
		fb.custom_minimum_size = Vector2(152, 62)
		fb.text = "ON FOOT\nrifle, grenades, legs"
		fb.add_theme_font_size_override("font_size", 12)
		fb.pressed.connect(_select.bind("foot"))
		_grid.add_child(fb)
		_cards["foot"] = fb
	var sea_ids := _sea_for(faction) if takes == "air" else []
	if takes == "air" and (not sea_ids.is_empty() or faction == "sea"):
		# The carrier first: she is the biggest thing afloat and she is not in
		# `Ship.KINDS`, so nothing would ever have listed her. She is American,
		# so she belongs on that page and on the ones that show everybody —
		# not under CHINA next to a Type 052D.
		if faction == "" or faction == "sea" or faction == "usa":
			var cb := Button.new()
			cb.custom_minimum_size = Vector2(152, 62)
			cb.text = "Fleet carrier\n%.0f m, %.0f kts" % [Carrier.LEN,
				Carrier.TOP_SPEED * 1.94384]
			cb.add_theme_font_size_override("font_size", 12)
			cb.pressed.connect(_select.bind("sea:carrier"))
			_grid.add_child(cb)
			_cards["sea:carrier"] = cb
		for k in sea_ids:
			var sd: Dictionary = Ship.KINDS[k]
			var sb := Button.new()
			sb.custom_minimum_size = Vector2(152, 62)
			sb.text = "%s\n%.0f m, %.0f kts" % [str(sd["name"]), float(sd["len"]),
				float(sd["speed"]) * 1.94384]
			sb.add_theme_font_size_override("font_size", 12)
			sb.pressed.connect(_select.bind("sea:" + k))
			_grid.add_child(sb)
			_cards["sea:" + k] = sb
		if faction == "sea":
			return
	# A national tab shows that country's ground fleet as well as its aircraft:
	# the vehicles carry a faction now, and hiding a Humvee from the UNITED
	# STATES page only to list it under GROUND was the wrong way round.
	var ground_ids := _ground_for(faction)
	if not ground_ids.is_empty():
		for k in ground_ids:
			var kd: Dictionary = Tank.KINDS[k]
			var vb := Button.new()
			vb.custom_minimum_size = Vector2(152, 62)
			vb.text = "%s\n%s" % [str(kd["name"]), VCLASS_NAMES.get(
				String(kd.get("class", "mbt")), "Vehicle")]
			vb.add_theme_font_size_override("font_size", 12)
			vb.pressed.connect(_select.bind("veh:" + k))
			_grid.add_child(vb)
			_cards["veh:" + k] = vb
		if faction == "ground":
			return
	for id in JetSpec.ids_for(faction):
		var spec := JetSpec.get_spec(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(152, 62)
		b.text = "%s\n%s" % [str(spec["name"]), str(spec["role"])]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_select.bind(id))
		_grid.add_child(b)
		_cards[id] = b

var _cqb_row: HBoxContainer
var _cqb_town: OptionButton
var _mode_box: VBoxContainer
var _veh_head: Label
var _frow: HBoxContainer

## What a mode lets you bring: "air" is the hangar as it always was, "ground"
## is wheels and tracks, "any" is all of it, "none" is your own two feet.
func mode_takes(id: String) -> String:
	# The three fought over a town take nothing from here at all: class,
	# weapons and vehicle are chosen on the deploy screen inside the match,
	# where they can be changed between lives.
	if id in ["cqb", "ground", "arms"]:
		return "none"
	return "air"

## Make the list of things to take agree with the mode that was picked.
func _apply_mode() -> void:
	var takes := mode_takes(mission_id)
	var town_fight: bool = takes != "air"
	if _cqb_row != null:
		_cqb_row.visible = town_fight
		if town_fight:
			_fill_cqb_towns()
	if _frow == null:
		return
	_frow.visible = takes == "air" or takes == "any"
	_grid.visible = takes != "none"
	_veh_head.text = "2   WHAT YOU TAKE" if takes != "none" \
		else "2   WHAT YOU TAKE — chosen on the deploy screen when the match starts: class, gunsmith, vehicle"
	if is_instance_valid(_stats):
		_stats.visible = takes != "none"
	if is_instance_valid(_blurb) and takes == "none":
		_blurb.text = "Pick the town above and launch.\n\nThe deploy screen comes up when the match starts and every time you go down: choose a class, set its weapons up on the gunsmith, and in the modes with vehicles choose what to go in as."
	if takes == "ground":
		faction = "ground"
	elif faction == "ground" and takes == "air":
		faction = ""
	_rebuild_cards()
	for k in _faction_btns:
		_faction_btns[k].modulate = Color(1, 1, 1) if k != faction else Color(0.55, 1.0, 0.75)
	# whatever was selected may not be on the list any more
	if takes == "ground" and not (jet_id.begins_with("veh:") or jet_id == "foot"):
		_select("foot")
	elif takes == "any" and jet_id.begins_with("sea:"):
		_select("foot")
	elif takes == "air" and jet_id == "foot":
		_select("f22")

func _cqb_pick(label: String, items: Array) -> OptionButton:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	_cqb_row.add_child(l)
	var ob := OptionButton.new()
	ob.add_theme_font_size_override("font_size", 12)
	ob.custom_minimum_size = Vector2(118, 30)
	for it in items:
		ob.add_item(String(it))
	_cqb_row.add_child(ob)
	return ob

## Every settlement on the map, home valley first. Filled when the row is
## first shown: the towns are sited while the world is built, which is after
## this screen is.
func _fill_cqb_towns() -> void:
	if _cqb_town.item_count > 0 or Scenery.current == null:
		return
	var sites: Array = Scenery.current.sites
	for i in sites.size():
		var t: Dictionary = sites[i]
		_cqb_town.add_item("%s  (%s)" % [String(t.get("name", "Town %d" % i)),
			"city" if float(t["r"]) > 1200.0 else ("town" if float(t["r"]) > 600.0 else "village")], i)
	for i in _cqb_town.item_count:
		if _cqb_town.get_item_id(i) == CqbMatch.town:
			_cqb_town.select(i)

func _fit() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vs := get_viewport_rect().size
	var panel_w := maxf(vs.x * 0.56, 620.0)
	if _panel:
		_panel.offset_right = panel_w
	if _root:
		_root.offset_right = -(vs.x - panel_w + 34.0)

func set_net_status(t: String) -> void:
	if _net_status:
		_net_status.text = t

## Shown from the pause menu's CHANGE MODE, over a match that is still going:
## RESUME goes back to it, LAUNCH ends it and starts whatever is picked here.
func set_paused(p: bool) -> void:
	paused = p
	_resume.visible = p
	if net_role != "client":
		_launch.text = "LAUNCH NEW" if p else "LAUNCH"

## What LAUNCH starts: the vehicle picked, or on foot in the modes where the
## kit is chosen inside the match, and the mode.
func launch_args() -> Array:
	return ["foot" if mode_takes(mission_id) == "none" else jet_id, mission_id]

func _select(id: String) -> void:
	jet_id = id
	if id == "foot":
		for k in _cards:
			_cards[k].modulate = Color(1, 1, 1) if k != id else Color(0.55, 1.0, 0.75)
		_blurb.text = "On foot\n\nTwo long guns and a sidearm, chosen above, and whatever you pick up off the road. Armour cannot be hurt with a rifle: a grenade underneath it can, and so can anything a run of kills lets you call in.\n\nF2 in the match lists the keys."
		for c in _stats.get_children():
			c.queue_free()
		return
	if id.begins_with("veh:"):
		for k in _cards:
			_cards[k].modulate = Color(1, 1, 1) if k != id else Color(0.55, 1.0, 0.75)
		var kd: Dictionary = Tank.KINDS[id.substr(4)]
		var vcl: String = String(kd.get("class", "mbt"))
		var indirect: bool = vcl == "spg" or vcl == "mlrs" or vcl == "tel"
		var how := "Direct fire. Put the crosshair on it and pull."
		if indirect:
			how = "Point the barrel at the ground where you want the rounds; the gun works out the elevation and charge."
		elif vcl == "lav":
			how = "A gun on the roof and no armour worth the name. It steers on its front wheels and it will outrun anything tracked; being seen is the thing that kills it."
		elif vcl == "sam":
			how = "Area air defence. It does not lay a gun: it acquires an aircraft, raises its rails and sends a round, and the round does the rest. Everything that makes it dangerous is in the missile."
		elif vcl == "spaag":
			how = "Short range air defence with a gun. Nothing else on the field can touch a helicopter at two kilometres, and it will shred anything soft on the ground too."
		elif vcl == "ifv":
			how = "An autocannon rather than a main gun: it fires fast and it will not trouble a tank's frontal armour, but it ruins everything softer."
		_blurb.text = "%s\n\n%s\n\nW/S drive, A/D steer, mouse lays the gun, SPACE fire, %sC sight, U to get out." % [
			str(kd["name"]), how, "" if vcl == "lav" else "V coax, "]
		for c in _stats.get_children():
			c.queue_free()
		var top: float = float(kd["top"]) * 3.6
		var vrows := [
			["ROLE", 1.0, vclass_of(id)],
			["TOP SPEED", clampf(top / 70.0, 0.05, 1.0), "%d km/h" % int(top)],
			["ARMOUR", clampf(float(kd["hp"]) / 320.0, 0.05, 1.0), "%d" % int(kd["hp"])],
			["GUN", clampf(float(kd["gun"]) / 1000.0, 0.05, 1.0), "%d" % int(kd["gun"])],
			# A machine gun does not reload, it cycles: the vehicles with one
			# were showing "0.0 s" and a full bar, which read as the fastest
			# gun on the field.
			["RELOAD" if vcl != "lav" else "RATE OF FIRE",
				clampf(1.0 - float(kd["reload"]) / 32.0, 0.05, 1.0) if vcl != "lav"
				else 1.0,
				"%.1f s" % float(kd["reload"]) if vcl != "lav"
				else "%d rpm" % int(60.0 / maxf(float(kd.get("mg_rate", 0.11)), 0.01))],
			["FIRE", 1.0, "indirect" if indirect else "direct"],
		]
		for r in vrows:
			_stats.add_child(_stat_row(str(r[0]), float(r[1]), str(r[2])))
		jet_changed.emit(id)
		return
	if id.begins_with("sea:"):
		# Anything afloat used to fall through to `JetSpec.get_spec`, so
		# choosing a destroyer showed you an aeroplane's thrust to weight ratio
		# and its wing loading.
		for k2 in _cards:
			_cards[k2].modulate = Color(1, 1, 1) if k2 != id else Color(0.55, 1.0, 0.75)
		_fill_sea(id.substr(4))
		jet_changed.emit(id)
		return
	for k in _cards:
		_cards[k].modulate = Color(1, 1, 1) if k != id else Color(0.55, 1.0, 0.75)
	var s := JetSpec.get_spec(id)
	var fac: Dictionary = JetSpec.FACTIONS.get(String(s.get("faction", "usa")), {})
	_blurb.text = "%s  ·  %s\n\n%s" % [str(fac.get("name", "")).capitalize(),
		str(fac.get("bloc", "")).to_upper(), s["blurb"]]
	for c in _stats.get_children():
		c.queue_free()
	var twr: float = s["thrust_ab"] / (s["mass"] * 9.81)
	var wl: float = s["mass"] / s["wing_area"]
	var rows := [
		["THRUST / WEIGHT", twr / 1.4, "%.2f" % twr],
		["WING LOADING", 1.0 - clampf((wl - 250.0) / 250.0, 0.0, 1.0), "%d kg/m2" % int(wl)],
		["ROLL RATE", s["roll_torque"] / s["inertia"].z / 9.0, "%d deg/s" % int(rad_to_deg(s["roll_torque"] / s["inertia"].z))],
		["INSTANT TURN", s["pitch_torque"] / s["inertia"].x / 3.0, "%.0f deg AoA" % rad_to_deg(s["cl_max_aoa"])],
		["FUEL", s["fuel"] / 10000.0, "%d kg" % int(s["fuel"])],
		["LOW OBSERVABLE", clampf(1.0 - s["stealth"] / 1.3, 0.0, 1.0), "%s" % ("internal bays" if s["bays"][0]["kind"] == "internal" else "external pylons")],
	]
	for r in rows:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = r[0]
		l.custom_minimum_size = Vector2(160, 0)
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		h.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110, 14)
		bar.show_percentage = false
		bar.value = clampf(r[1], 0.05, 1.0) * 100.0
		h.add_child(bar)
		var v := Label.new()
		v.text = " " + str(r[2])
		v.add_theme_font_size_override("font_size", 13)
		v.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		h.add_child(v)
		_stats.add_child(h)
	jet_changed.emit(id)

## What each ground vehicle class is called on its card and in the stats page.
const VCLASS_NAMES := {
	"mbt": "Main battle tank", "spg": "Self propelled gun",
	"mlrs": "Rocket artillery", "tel": "Missile launcher",
	"lav": "Light 4x4", "sam": "Air defence battery",
	"ifv": "Infantry fighting vehicle", "spaag": "Anti-aircraft gun",
}

func vclass_of(id: String) -> String:
	var kd: Dictionary = Tank.KINDS[id.substr(4)]
	return String(VCLASS_NAMES.get(String(kd.get("class", "mbt")), "Vehicle")).to_lower()

## The hulls on show under the current tab. Ships carry a faction now, so a
## national page lists that navy rather than everybody's.
func _sea_for(f: String) -> Array:
	var out: Array = []
	if f == "ground":
		return out
	for k in _crewable_ships():
		if f == "" or f == "sea" \
				or String(Ship.KINDS[k].get("faction", "")) == f:
			out.append(k)
	return out

## The ground fleet on show under the current tab: everything under GROUND and
## under ALL, that nation's own vehicles under a national tab, and nothing at
## all under NAVAL.
func _ground_for(f: String) -> Array:
	var out: Array = []
	if f == "sea":
		return out
	for k in Tank.KINDS:
		if f == "" or f == "ground" \
				or String(Tank.KINDS[k].get("faction", "")) == f:
			out.append(k)
	return out

## One labelled bar in the stats column.
func _stat_row(label: String, frac: float, value: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(160, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(110, 14)
	bar.show_percentage = false
	bar.value = clampf(frac, 0.05, 1.0) * 100.0
	h.add_child(bar)
	var v := Label.new()
	v.text = " " + value
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	h.add_child(v)
	return h

func _select_weather(id: String) -> void:
	for k in _weather_btns:
		_weather_btns[k].modulate = Color(1, 1, 1) if k != id else Color(0.55, 1.0, 0.75)
	weather_changed.emit(id)
	# Remembered between runs, along with the fly-by-wire and the radar range.
	Sim.weather = id
	Sim.save_settings()

## In a session the host picks the match and everybody flies it. A joiner who
## could choose for itself would either be quietly corrected a moment later or,
## worse, fly a different mission on the same connection.
var net_role := ""            # "", "host" or "client"

func set_net_role(role: String, host_mission: String) -> void:
	if role == net_role and (role != "client" or host_mission == mission_id):
		return
	net_role = role
	var locked := role == "client"
	for k in _mission_btns:
		_mission_btns[k].disabled = locked
		_mission_btns[k].tooltip_text = "the host chooses the match" if locked \
			else _mission_tip(k)
	if _launch != null:
		_launch.disabled = locked
		_launch.text = "HOST STARTS" if locked else "LAUNCH"
	if locked and host_mission != "" and host_mission != mission_id:
		_select_mission(host_mission)

func _mission_tip(id: String) -> String:
	for m in MISSIONS:
		if m[0] == id:
			return String(m[2])
	return ""

func _select_mission(id: String) -> void:
	mission_id = id
	_apply_mode()
	if net_role == "host":
		mission_changed.emit(id)
	for k in _mission_btns:
		_mission_btns[k].modulate = Color(1, 1, 1) if k != id else Color(0.55, 1.0, 0.75)
	for m in MISSIONS:
		if m[0] == id:
			var d := find_child("MissionDesc", true, false)
			if d:
				d.text = m[2]
