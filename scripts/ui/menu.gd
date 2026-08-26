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

const MISSIONS := [
	["takeoff", "RUNWAY START", "No threats. Cold on runway 36 — firewall it, rotate around 150 kt, gear up with G."],
	["free", "FREE FLIGHT", "No threats. Airborne over the valley with a full tank. Roam, then come back and land."],
	["landing", "APPROACH", "No threats. Twelve km final at 3000 ft — fly the PAPI down and grease it on."],
	["ramp", "RAMP WALK", "No threats. Start on foot beside the flight line — walk over and press E to climb into any jet."],
	["conquest", "CONQUEST", "Hostile. Five sectors across the valley — hold more than they do and their tickets bleed away."],
	["rush", "RUSH", "Hostile. Sectors open one at a time; smash the garrison or hold the ring to advance."],
	["warlords", "WARLORDS", "Hostile. Sequential sectors that pay command points as you take them."],
	["tdm", "TEAM DEATHMATCH", "Hostile. Two sides, first to twenty kills."],
	["ffa", "FREE FOR ALL", "Hostile. Everyone shoots everyone; twelve kills wins."],
	["carrier", "CARRIER TRAP", "No threats. Three miles behind the boat with the hook down."],
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
	title.text = "AFTERBURNER"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "select airframe"
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

	var frow := HBoxContainer.new()
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
	mgrid.columns = 4
	mgrid.add_theme_constant_override("h_separation", 8)
	mgrid.add_theme_constant_override("v_separation", 6)
	right.add_child(mgrid)
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

	var mdesc := Label.new()
	mdesc.name = "MissionDesc"
	mdesc.add_theme_font_size_override("font_size", 14)
	mdesc.add_theme_color_override("font_color", Color(0.62, 0.72, 0.82))
	right.add_child(mdesc)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	root.add_child(btns)
	_launch = Button.new()
	_launch.text = "LAUNCH"
	_launch.custom_minimum_size = Vector2(190, 52)
	_launch.add_theme_font_size_override("font_size", 20)
	_launch.pressed.connect(func(): start_requested.emit(jet_id, mission_id))
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

	var quit := Button.new()
	quit.text = "QUIT"
	quit.custom_minimum_size = Vector2(110, 52)
	quit.pressed.connect(func(): get_tree().quit())
	btns.add_child(quit)

	var help := Label.new()
	help.text = "W/S pitch  ·  A/D roll  ·  Q/E rudder  ·  SHIFT/CTRL throttle  ·  G gear  ·  F flaps  ·  X brakes\n" \
		+ "B bay doors  ·  1-4 pick weapon  ·  TAB cycle  ·  T target  ·  SPACE fire  ·  V gun  ·  N flares\n" \
		+ "C camera (cockpit / chase / orbit)  ·  M mouse stick  ·  H fly-by-wire  ·  R restart  ·  ESC menu"
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
		_select("veh:" + Tank.KINDS.keys()[0])
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
func _crewable_ships() -> Array:
	var out: Array = []
	for k in Ship.KINDS:
		if int(Ship.KINDS[k]["guns"]) > 0:
			out.append(k)
	return out

func _rebuild_cards() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	# aircraft first, then everything that drives, so the ground fleet is visible
	# without having to know the GROUND tab exists
	# a ship you can take command of: the ones with a gun on the foredeck
	if faction == "" or faction == "sea":
		for k in _crewable_ships():
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
	if faction == "" or faction == "ground":
		for k in Tank.KINDS:
			var kd: Dictionary = Tank.KINDS[k]
			var vb := Button.new()
			vb.custom_minimum_size = Vector2(152, 62)
			var vclass: String = {"mbt": "Main battle tank", "spg": "Self propelled gun",
				"mlrs": "Rocket artillery"}.get(String(kd.get("class", "mbt")), "Vehicle")
			vb.text = "%s\n%s" % [str(kd["name"]), vclass]
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

func set_paused(p: bool) -> void:
	paused = p
	_resume.visible = p
	_launch.text = "RESTART" if p else "LAUNCH"

func _select(id: String) -> void:
	jet_id = id
	if id.begins_with("veh:"):
		for k in _cards:
			_cards[k].modulate = Color(1, 1, 1) if k != id else Color(0.55, 1.0, 0.75)
		var kd: Dictionary = Tank.KINDS[id.substr(4)]
		var indirect: bool = String(kd.get("class", "mbt")) != "mbt"
		_blurb.text = "%s\n\n%s\n\nW/S drive, A/D steer, mouse lays the gun, SPACE fire, V coax, C sight, U to get out." % [
			str(kd["name"]),
			"Point the barrel at the ground where you want the rounds; the gun works out the elevation and charge." if indirect
			else "Direct fire. Put the crosshair on it and pull."]
		for c in _stats.get_children():
			c.queue_free()
		var top: float = float(kd["top"]) * 3.6
		var vrows := [
			["ROLE", 1.0, vclass_of(id)],
			["TOP SPEED", clampf(top / 70.0, 0.05, 1.0), "%d km/h" % int(top)],
			["ARMOUR", clampf(float(kd["hp"]) / 320.0, 0.05, 1.0), "%d" % int(kd["hp"])],
			["GUN", clampf(float(kd["gun"]) / 1000.0, 0.05, 1.0), "%d" % int(kd["gun"])],
			["RELOAD", clampf(1.0 - float(kd["reload"]) / 32.0, 0.05, 1.0),
				"%.1f s" % float(kd["reload"])],
			["FIRE", 1.0, "indirect" if indirect else "direct"],
		]
		for r in vrows:
			_stats.add_child(_stat_row(str(r[0]), float(r[1]), str(r[2])))
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

func vclass_of(id: String) -> String:
	var kd: Dictionary = Tank.KINDS[id.substr(4)]
	return {"mbt": "main battle tank", "spg": "self propelled gun",
		"mlrs": "rocket artillery"}.get(String(kd.get("class", "mbt")), "vehicle")

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
	if net_role == "host":
		mission_changed.emit(id)
	for k in _mission_btns:
		_mission_btns[k].modulate = Color(1, 1, 1) if k != id else Color(0.55, 1.0, 0.75)
	for m in MISSIONS:
		if m[0] == id:
			var d := find_child("MissionDesc", true, false)
			if d:
				d.text = m[2]
