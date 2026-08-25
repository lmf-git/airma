class_name AudioRig
extends Node
## Continuous audio for the flown aircraft: engine, afterburner, airflow, tyres,
## gun and the warning tones. One-shots are fired through Sfx.play_at.

var jet: Aircraft = null
var cockpit := true          # muffles the airflow when the canopy is shut

var _engine: AudioStreamPlayer
var _rotor: AudioStreamPlayer
var _roar: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _tyres: AudioStreamPlayer
var _gun: AudioStreamPlayer
var _warn: AudioStreamPlayer
var _buffet: AudioStreamPlayer
var _was_ground := true
var _gear_state := 1.0
var _bay_state := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_engine = _loop("engine", -10.0)
	_rotor = _loop("rotor", -60.0, false)
	_roar = _loop("roar", -60.0)
	_wind = _loop("wind", -60.0)
	_tyres = _loop("tyres", -60.0)
	_gun = _loop("gun", -60.0, false)
	_warn = _loop("beep", -60.0, false)
	_buffet = _loop("buffet", -60.0)

func _loop(id: String, db: float, autoplay := true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.get_clip(id)
	p.volume_db = db
	p.bus = "Master"
	add_child(p)
	if autoplay:
		p.play()
	return p

func _db(linear: float) -> float:
	return -80.0 if linear <= 0.0008 else linear_to_db(clampf(linear, 0.0, 1.4))

func _process(delta: float) -> void:
	if jet == null or not is_instance_valid(jet):
		return
	var alive := jet.alive
	var power: float = jet.power if alive else 0.0
	var rotary: bool = bool(jet.spec.get("rotary", false))
	var ab: float = clampf((power - 0.78) / 0.22, 0.0, 1.0)
	var speed := jet.linear_velocity.length()
	var muffle: float = 0.55 if cockpit else 1.0

	if rotary:
		# rotor RPM barely changes; collective changes how hard it is working
		if not _rotor.playing:
			_rotor.play()
		_rotor.pitch_scale = lerpf(_rotor.pitch_scale, 0.82 + power * 0.26,
			clampf(delta * 2.0, 0, 1))
		_rotor.volume_db = _db((0.30 + power * 0.55) * muffle)
		_engine.pitch_scale = 1.35
		_engine.volume_db = _db((0.05 + power * 0.14) * muffle)
		_roar.volume_db = _db(0.0)
		if _roar.playing:
			_roar.stop()
	else:
		if _rotor.playing:
			_rotor.stop()
		_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.70 + power * 0.62,
			clampf(delta * 3.0, 0, 1))
		_engine.volume_db = _db((0.16 + power * 0.55) * muffle)
		_roar.pitch_scale = 0.85 + power * 0.35
		_roar.volume_db = _db((0.05 + ab * 0.75) * muffle)
		if ab > 0.02 and not _roar.playing:
			_roar.play()

	# airflow rises with dynamic pressure, and you hear more of it with the
	# gear, bay or airbrake hanging out
	var q: float = clampf(speed / 340.0, 0.0, 1.6)
	var dirty: float = 1.0 + 0.5 * jet.gear_anim + 0.6 * jet.air_anim + 0.4 * jet.canopy_anim
	_wind.pitch_scale = 0.75 + q * 0.6
	_wind.volume_db = _db(q * q * 0.55 * dirty * (0.75 if cockpit else 1.0))
	if not _wind.playing:
		_wind.play()

	var rolling: float = 1.0 if (jet.on_ground and alive) else 0.0
	_tyres.volume_db = _db(rolling * clampf(speed / 70.0, 0.0, 1.0) * 0.55)
	_tyres.pitch_scale = 0.7 + clampf(speed / 90.0, 0.0, 1.2)
	if rolling > 0.0 and not _tyres.playing:
		_tyres.play()

	_buffet.volume_db = _db(0.5 if (jet.stalling and alive) else 0.0)
	if jet.stalling and alive and not _buffet.playing:
		_buffet.play()
	elif not jet.stalling and _buffet.playing and _buffet.volume_db < -70.0:
		_buffet.stop()

	# warning tone: missile inbound beats low fuel
	var warn := jet.missile_warn > 0.0 and alive
	if warn and not _warn.playing:
		_warn.play()
	elif not warn and _warn.playing:
		_warn.stop()
	_warn.volume_db = _db(0.75 if warn else 0.0)

	# gun buzz while the trigger is down
	var firing: bool = alive and jet.gun_cd > 0.0 and jet.ammo > 0
	if firing and not _gun.playing:
		_gun.play()
	elif not firing and _gun.playing:
		_gun.stop()
	_gun.volume_db = _db(0.9 if firing else 0.0)

	# servo and touchdown one-shots
	if absf(jet.gear_anim - _gear_state) > 0.02 and _gear_state in [0.0, 1.0]:
		Sfx.play_at(get_tree().current_scene, "servo", jet.global_position, -4.0, 0.9)
	_gear_state = jet.gear_anim
	var bay := 0.0
	for k in jet.bays:
		bay = maxf(bay, jet.bays[k]["anim"] if jet.bays[k]["kind"] == "internal" else 0.0)
	if absf(bay - _bay_state) > 0.02 and _bay_state in [0.0, 1.0]:
		Sfx.play_at(get_tree().current_scene, "servo", jet.global_position, -7.0, 1.25)
	_bay_state = bay
	if jet.on_ground and not _was_ground and alive:
		Sfx.play_at(get_tree().current_scene, "thump", jet.global_position,
			clampf(-14.0 + absf(jet.vspeed) * 1.6, -18.0, 2.0))
	_was_ground = jet.on_ground

func set_paused(p: bool) -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			c.stream_paused = p
