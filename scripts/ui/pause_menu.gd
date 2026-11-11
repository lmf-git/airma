class_name PauseMenu
extends Control
## What ESC brings up in a match.
##
## ESC used to bring the whole hangar back -- the mode grid, every vehicle, the
## weather and the multiplayer row -- with RESUME tucked in among them, and
## there was nowhere at all to set the volume or the mouse. Pausing is a short
## list now. Choosing a different mode is one entry on it, and the settings are
## their own page, which the hangar opens as well.

signal resume_requested()
signal restart_requested()
signal change_mode_requested()

const ACCENT := Color(0.62, 0.92, 1.0)
const DIM := Color(0.6, 0.7, 0.8)
const TEXT := Color(0.85, 0.92, 1.0)
const AUDIO_ROWS := [
	[&"Master", "MASTER"],
	[&"Effects", "WEAPONS & WORLD"],
	[&"Engines", "ENGINES & VEHICLES"],
	[&"Interface", "ALERTS & HIT MARKS"],
]

var world: Node = null
## Opened from the hangar rather than from a match: there is no pause page
## behind it, so BACK and ESC close it.
var standalone := false

var _main: VBoxContainer
var _settings: VBoxContainer
var _scroll: ScrollContainer
var _context: Label
var _resume: Button
var _restart: Button
var _quit: Button
var _quit_armed := false
var _vol_sliders := {}
var _vol_labels := {}
var _gain: HSlider
var _gain_label: Label
var _invert: CheckButton
var _assist: CheckButton
var _radar: OptionButton
var _fullscreen: CheckButton
var _vsync: CheckButton
var _back: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# Parented straight to a CanvasLayer, so there is no size to inherit: see
	# the same note in `Menu`.
	_fit()
	get_viewport().size_changed.connect(_fit)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09, 0.95)
	sb.border_color = Color(ACCENT, 0.45)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(34.0)
	box.add_theme_stylebox_override("panel", sb)
	centre.add_child(box)
	var stack := VBoxContainer.new()
	box.add_child(stack)
	_build_main(stack)
	_build_settings(stack)
	_fit()

func _fit() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _scroll != null:
		var vs := get_viewport_rect().size
		_scroll.custom_minimum_size = Vector2(600.0, clampf(vs.y - 300.0, 240.0, 560.0))

# ------------------------------------------------------------------ pages
func _build_main(parent: Control) -> void:
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	parent.add_child(_main)
	_main.add_child(_label("PAUSED", 40, ACCENT))
	_context = _label("", 14, DIM)
	_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context.custom_minimum_size = Vector2(340, 0)
	_main.add_child(_context)
	_main.add_child(_gap(6))
	_resume = _button(_main, "RESUME", func() -> void: resume_requested.emit())
	_button(_main, "SETTINGS", _show_settings)
	_button(_main, "CHANGE MODE / VEHICLE", func() -> void: change_mode_requested.emit())
	_restart = _button(_main, "RESTART MATCH", func() -> void: restart_requested.emit())
	_main.add_child(_gap(6))
	_quit = _button(_main, "QUIT TO DESKTOP", _on_quit)
	_main.add_child(_gap(2))
	_main.add_child(_label("ESC to resume", 12, DIM))

func _build_settings(parent: Control) -> void:
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 10)
	_settings.visible = false
	parent.add_child(_settings)
	_settings.add_child(_label("SETTINGS", 34, ACCENT))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_scroll.add_child(body)

	_section(body, "AUDIO")
	for r in AUDIO_ROWS:
		_volume_row(body, r[0], String(r[1]))

	_section(body, "CONTROLS")
	var gh := _row(body, "MOUSE SENSITIVITY")
	_gain = HSlider.new()
	_gain.min_value = 0.2
	_gain.max_value = 3.0
	_gain.step = 0.05
	_gain.custom_minimum_size = Vector2(240, 24)
	_gain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gain.value_changed.connect(func(v: float) -> void:
		Sim.mouse_gain = v
		_gain_label.text = "%.2f×" % v)
	gh.add_child(_gain)
	_gain_label = _label("", 14, TEXT)
	_gain_label.custom_minimum_size = Vector2(64, 0)
	gh.add_child(_gain_label)
	_invert = _check(body, "INVERT MOUSE Y", func(on: bool) -> void: Sim.invert_pitch = on)

	_section(body, "FLIGHT")
	_assist = _check(body, "FLIGHT ASSIST", _set_assist)
	_assist.tooltip_text = "Fly-by-wire on aeroplanes, the stability system on helicopters. %s toggles it in the air." \
		% Sim.key_label(&"assist")
	var rh := _row(body, "RADAR RANGE")
	_radar = OptionButton.new()
	_radar.add_theme_font_size_override("font_size", 14)
	_radar.custom_minimum_size = Vector2(140, 30)
	for i in Sim.RADAR_RANGES.size():
		_radar.add_item("%d km" % int(float(Sim.RADAR_RANGES[i]) * 0.001), i)
	_radar.item_selected.connect(func(i: int) -> void: Sim.radar_range_idx = i)
	rh.add_child(_radar)

	_section(body, "DISPLAY")
	_fullscreen = _check(body, "FULLSCREEN", func(on: bool) -> void:
		Sim.fullscreen = on
		Sim.apply_display(true))
	_vsync = _check(body, "VSYNC", func(on: bool) -> void:
		Sim.vsync = on
		Sim.apply_display(true))

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	_settings.add_child(_gap(4))
	_settings.add_child(foot)
	_back = _button(foot, "BACK", func() -> void: back())
	_back.custom_minimum_size = Vector2(180, 46)
	var d := _button(foot, "DEFAULTS", _defaults)
	d.custom_minimum_size = Vector2(150, 46)

# ------------------------------------------------------------------ api
## Up over a match. `can_restart` is false for a joiner: the host runs the
## match, and a joiner restarting it on its own would leave the session.
func open(context: String, can_restart: bool) -> void:
	standalone = false
	_context.text = context
	_restart.disabled = not can_restart
	_restart.tooltip_text = "" if can_restart else "the host chooses the match"
	_show_main()
	visible = true
	_resume.grab_focus()

## The settings page alone, over the hangar.
func open_settings() -> void:
	standalone = true
	visible = true
	_show_settings()

func close() -> void:
	if visible and _settings.visible:
		Sim.save_settings()
	visible = false
	_disarm_quit()

## One step out, for ESC and BACK. False when there is nothing left to step
## out of here and the caller should resume the match.
func back() -> bool:
	if not visible:
		return false
	if _settings.visible:
		Sim.save_settings()
		if standalone:
			close()
		else:
			_show_main()
			_resume.grab_focus()
		return true
	return false

# ------------------------------------------------------------------ internals
func _show_main() -> void:
	_settings.visible = false
	_main.visible = true
	_disarm_quit()

func _show_settings() -> void:
	_refresh()
	_main.visible = false
	_settings.visible = true
	_back.text = "BACK" if not standalone else "DONE"
	_scroll.scroll_vertical = 0

## Whatever the values are now: the assist and the radar range are changed
## from the cockpit too, not only from here.
func _refresh() -> void:
	for b in _vol_sliders:
		var v: float = float(Sim.volumes.get(b, 1.0))
		(_vol_sliders[b] as HSlider).set_value_no_signal(v * 100.0)
		(_vol_labels[b] as Label).text = "%d%%" % roundi(v * 100.0)
	_gain.set_value_no_signal(Sim.mouse_gain)
	_gain_label.text = "%.2f×" % Sim.mouse_gain
	_invert.set_pressed_no_signal(Sim.invert_pitch)
	_assist.set_pressed_no_signal(Sim.assist)
	_radar.select(clampi(Sim.radar_range_idx, 0, Sim.RADAR_RANGES.size() - 1))
	_fullscreen.set_pressed_no_signal(Sim.fullscreen)
	_vsync.set_pressed_no_signal(Sim.vsync)

func _defaults() -> void:
	for b in Sim.volumes:
		Sim.volumes[b] = 1.0
	Sim.apply_audio()
	Sim.mouse_gain = 1.0
	Sim.invert_pitch = false
	_set_assist(true)
	Sim.radar_range_idx = 2
	Sim.vsync = true
	Sim.fullscreen = false
	Sim.apply_display(true)
	_refresh()

## The default for the next aircraft, and the one being flown now.
func _set_assist(on: bool) -> void:
	Sim.assist = on
	var p: Variant = world.get("player") if world != null else null
	if p != null and is_instance_valid(p) and "assist" in p:
		p.set("assist", on)

func _on_quit() -> void:
	if not _quit_armed:
		_quit_armed = true
		_quit.text = "QUIT — PRESS AGAIN"
		_quit.modulate = Color(1.0, 0.6, 0.55)
		return
	Sim.save_settings()
	get_tree().quit()

func _disarm_quit() -> void:
	_quit_armed = false
	if _quit != null:
		_quit.text = "QUIT TO DESKTOP"
		_quit.modulate = Color(1, 1, 1)

# ------------------------------------------------------------------ widgets
func _label(t: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _button(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(340, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _section(parent: Control, t: String) -> void:
	parent.add_child(_gap(4))
	parent.add_child(_label(t, 14, ACCENT))
	var rule := ColorRect.new()
	rule.color = Color(ACCENT, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	parent.add_child(rule)

func _row(parent: Control, t: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := _label(t, 14, DIM)
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	return h

func _volume_row(parent: Control, bus: StringName, t: String) -> void:
	var h := _row(parent, t)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var v := _label("", 14, TEXT)
	v.custom_minimum_size = Vector2(64, 0)
	h.add_child(v)
	_vol_sliders[bus] = s
	_vol_labels[bus] = v
	s.value_changed.connect(func(x: float) -> void:
		Sim.volumes[bus] = x / 100.0
		v.text = "%d%%" % roundi(x)
		Sim.apply_audio())

func _check(parent: Control, t: String, cb: Callable) -> CheckButton:
	var h := _row(parent, t)
	var c := CheckButton.new()
	c.toggled.connect(cb)
	h.add_child(c)
	return c
