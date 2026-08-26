class_name ChatBox
extends Control
## Text chat. `/` opens the line, Enter sends it, Escape throws it away. The
## backlog stays on screen for a while after the last message and then fades,
## so it is readable in a fight without permanently covering the left of the
## canopy.

const HOLD := 9.0             # seconds a message stays at full strength
const FADE := 3.0             # and how long it takes to go
const KEEP := 40              # backlog depth

var typing := false
var draft := ""
var log_lines: Array = []     # {who, text, team, at}
var _caret := 0.0
var _font: Font
var _small := 15
var _line := 19

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A Control draws before its children; nothing is parented here, but the
	# chat has to sit over the HUD rather than under it.
	z_index = 40
	_font = ThemeDB.fallback_font
	set_process(true)

## Something happened that everybody should see, without anyone typing it.
func system(text: String) -> void:
	log_lines.append({"who": "", "text": text, "team": -1,
		"at": Time.get_ticks_msec() * 0.001})
	_trim()

func post(who: String, text: String, team: int) -> void:
	log_lines.append({"who": who, "text": text, "team": team,
		"at": Time.get_ticks_msec() * 0.001})
	_trim()

func _trim() -> void:
	while log_lines.size() > KEEP:
		log_lines.pop_front()
	queue_redraw()

func open_line() -> void:
	typing = true
	draft = ""
	_caret = 0.0
	queue_redraw()

func close_line() -> void:
	typing = false
	draft = ""
	queue_redraw()

## Everything goes through here while the line is open, so that typing "w" is a
## letter and not full throttle. Returns true when the event was consumed.
func handle_key(e: InputEventKey) -> bool:
	if not typing or not e.pressed:
		return typing
	match e.keycode:
		KEY_ESCAPE:
			close_line()
			Sim.typing = false
			return true
		KEY_ENTER, KEY_KP_ENTER:
			var out := draft.strip_edges()
			close_line()
			Sim.typing = false
			if out != "":
				send(out)
			return true
		KEY_BACKSPACE:
			draft = draft.substr(0, maxi(draft.length() - 1, 0))
			queue_redraw()
			return true
	var ch := char(e.unicode)
	if e.unicode >= 32 and draft.length() < 140:
		draft += ch
		queue_redraw()
	return true

## Out over the wire if there is a wire, and onto our own screen either way.
func send(text: String) -> void:
	var me := "You"
	var team := 0
	if Sim.net != null and Sim.net.active:
		me = "P%d" % Sim.net.my_id
		Sim.net.say(text)
		return                     # the RPC calls back into post() locally
	post(me, text, team)

func _process(delta: float) -> void:
	if typing:
		_caret = fmod(_caret + delta, 1.0)
		queue_redraw()
	elif not log_lines.is_empty():
		var newest: float = float(log_lines[-1]["at"])
		if Time.get_ticks_msec() * 0.001 - newest < HOLD + FADE + 0.5:
			queue_redraw()

func _draw() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var x := 22.0
	var y := size.y - 132.0
	# newest at the bottom, walking up
	var shown := 0
	for i in range(log_lines.size() - 1, -1, -1):
		if shown >= 8:
			break
		var e: Dictionary = log_lines[i]
		var age: float = now - float(e["at"])
		var a := 1.0
		if not typing:
			if age > HOLD + FADE:
				break
			a = clampf(1.0 - (age - HOLD) / FADE, 0.0, 1.0)
		if a <= 0.01:
			break
		var who := String(e["who"])
		var body := String(e["text"])
		var col := Color(0.86, 0.90, 0.94, a)
		var name_col := Color(0.55, 0.85, 1.0, a)
		if int(e["team"]) < 0:
			col = Color(0.98, 0.82, 0.42, a)   # system
		var text := body if who == "" else "%s:  %s" % [who, body]
		var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_small).x
		draw_rect(Rect2(x - 6.0, y - float(_line) + 4.0, w + 12.0, float(_line)),
			Color(0.03, 0.05, 0.07, 0.45 * a))
		if who != "":
			var nw: float = _font.get_string_size("%s:  " % who,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small).x
			draw_string(_font, Vector2(x, y), "%s:  " % who,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small, name_col)
			draw_string(_font, Vector2(x + nw, y), body,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small, col)
		else:
			draw_string(_font, Vector2(x, y), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _small, col)
		y -= float(_line)
		shown += 1
	if not typing:
		return
	var ly := size.y - 104.0
	var caret := "_" if _caret < 0.5 else " "
	var prompt := "SAY:  %s%s" % [draft, caret]
	var pw: float = _font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_small).x
	draw_rect(Rect2(x - 8.0, ly - float(_line) + 4.0, maxf(pw + 16.0, 320.0),
		float(_line) + 4.0), Color(0.03, 0.06, 0.09, 0.78))
	draw_rect(Rect2(x - 8.0, ly - float(_line) + 4.0, maxf(pw + 16.0, 320.0),
		float(_line) + 4.0), Color(0.45, 0.72, 0.92, 0.5), false, 1.0)
	draw_string(_font, Vector2(x, ly), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_small, Color(0.92, 0.96, 1.0))
