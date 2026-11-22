class_name KeyBindings
extends RefCounted
## The input map: every action and the keys, buttons and axes bound to it,
## installed at boot, and the name of the key an action is on for the pages that
## tell you which to press.
##
## Split out of `sim.gd`; reached as `Sim.keys`.


## Godot spells these out -- "Space", "Backslash", "BracketLeft" -- and a HUD
## strip has room for a glyph.
const _KEY_NAMES := {
	KEY_SPACE: "SPACE", KEY_ESCAPE: "ESC", KEY_TAB: "TAB",
	KEY_BACKSLASH: "\\", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
	KEY_APOSTROPHE: "'", KEY_SEMICOLON: ";", KEY_MINUS: "-", KEY_EQUAL: "=",
	KEY_SHIFT: "SHIFT", KEY_CTRL: "CTRL", KEY_ALT: "ALT", KEY_META: "CMD",
}

func label(action: StringName, fallback := "?") -> String:
	if not InputMap.has_action(action):
		return fallback
	for e in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null:
			return _key_name(k.physical_keycode)
	# nothing on the keyboard: say so rather than naming a key that is not bound
	for e2 in InputMap.action_get_events(action):
		if e2 is InputEventMouseButton:
			return "LMB" if (e2 as InputEventMouseButton).button_index \
				== MOUSE_BUTTON_LEFT else "RMB"
	return fallback

func _key_name(code: int) -> String:
	if _KEY_NAMES.has(code):
		return String(_KEY_NAMES[code])
	return OS.get_keycode_string(code).to_upper()

func _add(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, 0.15)
	for e in events:
		InputMap.action_add_event(action, e)

## A gamepad button, and a stick axis with the half of it that is wanted.
## There was no joypad support at all: `InputEventJoypad` appeared nowhere, so a
## flight simulator was keyboard and mouse only.
func _btn(idx: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	return e

func _axis(idx: JoyAxis, sign_of: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = idx
	e.axis_value = sign_of
	return e

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mb(idx: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	return e

func install() -> void:
	# The stick, on the keyboard and on an actual stick. Left stick flies,
	# right stick looks, triggers work the guns, and the shoulders are the
	# throttle — the layout anything with two sticks already expects.
	_add(&"pitch_up",     [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add(&"pitch_down",   [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add(&"roll_left",    [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add(&"roll_right",   [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add(&"yaw_left",     [_key(KEY_Q), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add(&"yaw_right",    [_key(KEY_E), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add(&"throttle_up",  [_key(KEY_SHIFT), _btn(JOY_BUTTON_RIGHT_SHOULDER)])
	_add(&"throttle_down",[_key(KEY_CTRL), _key(KEY_Z), _btn(JOY_BUTTON_LEFT_SHOULDER)])
	_add(&"brakes",       [_key(KEY_X)])
	_add(&"gear",         [_key(KEY_G)])
	_add(&"bay",          [_key(KEY_B)])
	_add(&"flaps",        [_key(KEY_F)])
	# Left click is the trigger, everywhere. Right click is deliberately NOT a
	# weapon: it is the sensor page chord with ALT, and having it also launch
	# meant reaching for the pod put a missile off the rail.
	_add(&"fire",         [_key(KEY_SPACE), _mb(MOUSE_BUTTON_LEFT), _btn(JOY_BUTTON_A)])
	# On foot the two have to come apart. `fire` carries both the space bar and
	# the left button because that is what a cockpit wants, but a man on the
	# ground jumps with one and shoots with the other -- bound together,
	# clicking made him jump instead of firing.
	_add(&"jump",         [_key(KEY_SPACE)])
	_add(&"foot_fire",    [_mb(MOUSE_BUTTON_LEFT)])
	# Sights and reload, on foot. The right button is the sensor page in a
	# cockpit and R is a submarine's ballast -- neither of which a man on the
	# ground has, so the keys are free where he is standing.
	_add(&"ads",          [_mb(MOUSE_BUTTON_RIGHT)])
	_add(&"reload",       [_key(KEY_R)])
	# G is the undercarriage in a cockpit, and a man on foot has none.
	_add(&"grenade",      [_key(KEY_G)])
	# X is the wheel brakes in a cockpit
	_add(&"flashbang",    [_key(KEY_X)])
	# and F is the flaps
	_add(&"pickup",       [_key(KEY_F)])
	# Z is the look-behind in a cockpit
	_add(&"prone",        [_key(KEY_Z)])
	# V is the dedicated cannon key. It is off the mouse: left click already
	# pulls the trigger, and having both meant one click fired the gun and a
	# missile at the same time.
	# Moved off V, which the chaff now has. K is the only letter left free.
	_add(&"gun",          [_key(KEY_K), _btn(JOY_BUTTON_X)])
	_add(&"cycle_weapon", [_key(KEY_BACKSLASH), _btn(JOY_BUTTON_B)])
	_add(&"action_menu",  [_key(KEY_TAB), _btn(JOY_BUTTON_BACK)])
	_add(&"weapon_1",     [_key(KEY_1)])
	_add(&"weapon_2",     [_key(KEY_2)])
	_add(&"weapon_3",     [_key(KEY_3)])
	_add(&"weapon_4",     [_key(KEY_4)])
	# a loaded strike aircraft carries more than four types now
	_add(&"weapon_5",     [_key(KEY_5)])
	_add(&"weapon_6",     [_key(KEY_6)])
	_add(&"weapon_7",     [_key(KEY_7)])
	_add(&"weapon_8",     [_key(KEY_8)])
	_add(&"cycle_target", [_key(KEY_T), _btn(JOY_BUTTON_Y)])
	# C is flares now, so the view moved to P. Night vision wanted a key that
	# works in every seat and every view, and N was the obvious one.
	_add(&"camera",       [_key(KEY_P), _btn(JOY_BUTTON_RIGHT_STICK)])
	_add(&"night_vision", [_key(KEY_N)])
	_add(&"look_back",    [_key(KEY_Z)])
	_add(&"freelook",     [_key(KEY_ALT), _key(KEY_META)])
	_add(&"interact",     [_key(KEY_U)])
	_add(&"crouch",       [_key(KEY_CTRL), _key(KEY_C)])
	_add(&"panel_left",   [_key(KEY_BRACKETLEFT)])
	_add(&"panel_right",  [_key(KEY_BRACKETRIGHT)])
	_add(&"laser",        [_key(KEY_L)])
	# Lights share the laser's key. The laser is only meaningful with the sensor
	# page up, and the lamp only matters when it is not, so the one key does
	# whichever of the two makes sense where you are.
	_add(&"lights",       [_key(KEY_L)])
	# Not G: that is the landing gear, and on the gunship the two fought over
	# the same key — you could not raise the gear without being thrown into the
	# battery, or take the battery without cycling the gear.
	_add(&"gunner_station", [_key(KEY_J)])
	_add(&"radar_out",    [_key(KEY_EQUAL)])
	_add(&"radar_in",     [_key(KEY_MINUS)])
	# Depth, on the two keys directly above one another: R rises, F floods.
	# Page Up and Page Down are nowhere near the hand that is already on the
	# helm. A submarine reads none of the aircraft actions these share a key
	# with -- it has no flaps and no gun -- and an aeroplane never dives or
	# surfaces, so the pairs cannot both be live on the same vehicle.
	_add(&"dive",         [_key(KEY_F)])
	_add(&"surface",      [_key(KEY_R)])
	_add(&"pause_menu",   [_key(KEY_ESCAPE), _btn(JOY_BUTTON_START)])
	_add(&"assist",       [_key(KEY_H)])
	# Countermeasures together under the left hand. Chaff was on B, which is
	# also the bomb bay -- so every bundle of chaff opened the bay doors.
	_add(&"flare",        [_key(KEY_C), _btn(JOY_BUTTON_DPAD_UP)])
	_add(&"chaff",        [_key(KEY_V), _btn(JOY_BUTTON_DPAD_DOWN)])
	# on foot the same key: chaff is an aircraft's, fire select a rifle's
	_add(&"fire_mode",    [_key(KEY_V), _btn(JOY_BUTTON_DPAD_DOWN)])
	_add(&"mouse_fly",    [_key(KEY_SEMICOLON)])
	_add(&"map",          [_key(KEY_M), _key(KEY_F1)])
	# Not backslash: `cycle_weapon` is already there, and `tapped` erases the
	# press when it is read, so whichever of the two was polled first that frame
	# ate the other. Cycling the weapon and slowing time fought over one key.
	_add(&"time_slow",    [_key(KEY_APOSTROPHE)])
