class_name WalkerArms
extends RefCounted
## What a man's hands do with weapons: changing them, the trigger and the selector, reloading, throwing, the launchers' seeker, the mortar on the ground, and the sights' power. Split out of `walker.gd`; every walker has one as `arms`.

var w: Walker

var _throw_flash := false

## The mortar, when it is set up on the ground rather than carried.
var tube: MortarTube = null

var _tone_t := 0.0

var _burst_left := 0

var _queued := 0.0

var _reload_mark := 0

var _reload_empty := false

var _cycle_snd := "pump"

func _init(owner_node: Walker) -> void:
	w = owner_node

## Everything the hands do in a tick: change weapon, reload, throw, shoot.
func _fight(delta: float) -> void:
	w._shot_cd = maxf(w._shot_cd - delta, 0.0)
	_queued = maxf(_queued - delta, 0.0)
	w._bloom = maxf(w._bloom - delta * 0.035, 0.0)
	w._recoil = lerpf(w._recoil, 0.0, clampf(delta * 8.0, 0, 1))
	w.hit_t = maxf(w.hit_t - delta, 0.0)
	w.kill_t = maxf(w.kill_t - delta, 0.0)
	w.hurt_t = maxf(w.hurt_t - delta, 0.0)
	w._since_hit += delta
	w._supp_quiet += delta
	if w._supp_quiet > 0.8:
		w.suppression = maxf(w.suppression - delta * 0.35, 0.0)
	if w.regen and w._since_hit > 5.0 and w.suppression < 0.25 and w.health < 100.0:
		w.health = minf(w.health + delta * 22.0, 100.0)
	var world := w.get_tree().current_scene
	var g: Dictionary = w.gun_spec()

	for wi in w.slots.size():
		if Sim.tapped(StringName("weapon_%d" % (wi + 1))) and wi != w.slot and w._grab_t < 0.0:
			w._rounds[w.kit_idx] = w.ammo
			w._spare[w.kit_idx] = w.spare
			w.slot = wi
			w._take_up(int(w.slots[wi]))
			return
	var want_frag: bool = Sim.tapped(&"grenade") and w.grenades > 0
	var want_flash: bool = Sim.tapped(&"flashbang") and w.flashes > 0
	if (want_frag or want_flash) and w._shot_cd < 0.2 and w._throw_t < 0.0 \
			and w.reloading <= 0.0:
		_throw_flash = want_flash and not want_frag
		w._throw_t = 0.0
		w._shot_cd = 0.75
		Sfx.play_ui(world, "pin", -6.0)
	if w._throw_t >= 0.0:
		# it leaves the hand when the arm comes through, not when the key
		# goes down
		var was_t := w._throw_t
		w._throw_t += delta / 0.62
		if was_t < 0.62 and w._throw_t >= 0.62:
			_throw()
		if w._throw_t >= 1.0:
			w._throw_t = -1.0

	# The shotgun has to be worked between shots.
	if w._pump_in > 0.0:
		w._pump_in -= delta
		if w._pump_in <= 0.0:
			Sfx.play_at(world, _cycle_snd, w.global_position + Vector3(0, 1.4, 0), -8.0,
				randf_range(0.95, 1.05), 60.0)

	var full: int = int(g["mag"])
	if w.binos and w._trigger():
		# the first pull puts the glasses down; it takes a second to shoot
		w.binos = false
		w._ui_click = true
	w._steady(delta)
	# the selector
	if Sim.tapped(&"fire_mode"):
		var ms: Array = Walker.modes_of(g)
		if ms.size() > 1:
			var nxt: String = String(ms[(ms.find(w.mode_now()) + 1) % ms.size()])
			w.fire_mode[w.kit_idx] = nxt
			_burst_left = 0
			Sfx.play_ui(world, "clink", -12.0, 1.3)
			Sim.report("%s — %s" % [String(g["name"]), nxt.to_upper()], Sim.Ev.INFO)
	var pulled: bool = w._trigger() and w._block < 0.4
	var edge: bool = pulled and not w._trigger_was
	w._trigger_was = pulled
	if Sim.tapped(&"reload") and w.reloading <= 0.0 and w.ammo < full and w.spare > 0:
		_begin_reload(g)
	if w.reloading > 0.0:
		_work_reload(delta, g, edge)
		return
	if String(g.get("launcher", "")) == "mortar":
		_work_mortar(delta, g, edge)
		return

	# Down the sights it goes where it is pointed; from the hip it does not.
	var s: float = lerpf(float(g["hip"]), float(g["ads"]), w._ads)
	var loose: float = 1.0 - 0.75 * w._ads
	if w.prone:
		s *= 0.45
	elif w.crouching:
		s *= 0.7
	s += clampf(Vector2(w.vel.x, w.vel.z).length() / Walker.RUN, 0.0, 1.0) * float(g["hip"]) * 1.4 * loose
	if not w.on_floor:
		s += float(g["hip"]) * 2.0
	s += w._bloom * loose
	# under fire: nobody holds a sight picture with rounds cracking past
	s = s * (1.0 + 1.2 * w.suppression) + float(g["hip"]) * 0.5 * w.suppression
	w.spread_now = s

	if edge:
		_queued = 0.12
	_seek(delta, g)
	var mode: String = w.mode_now()
	if edge and mode == "burst":
		_burst_left = 3
	var want: bool
	match mode:
		"auto":
			want = pulled
		"burst":
			want = _burst_left > 0
		_:
			want = _queued > 0.0
	if not want or w._shot_cd > 0.0 or w.body._ready_s < 0.75:
		return
	_queued = 0.0
	if _burst_left > 0:
		_burst_left -= 1
	if w.ammo <= 0:
		_burst_left = 0
		if edge or mode != "auto":
			Sfx.play_ui(world, "dry", -6.0)
		if w.spare > 0:
			_begin_reload(g)
		else:
			w._shot_cd = 0.25
		return
	w._shot_cd = float(g["cd"])
	w.ammo -= 1
	w._rounds[w.kit_idx] = w.ammo
	var from: Vector3 = w.body.muzzle_pos()
	# The round leaves the muzzle but it goes where the eye is looking: find
	# what is under the crosshair and send it there. Fired parallel to the
	# view instead, a rifle held beside the head puts every shot a hand's
	# width off, and a camera over the shoulder puts them a pace off.
	var look := -w._aim_xf.basis.z
	var eye := w._aim_xf.origin
	var skip: float = maxf((w.body.eye_pos() - eye).dot(look), 0.0) + 0.6
	var start: Vector3 = eye + look * skip
	# What is under the crosshair: the first wall, prop or piece of ground the
	# line of sight meets.
	#
	# Ground under the crosshair used to be pushed out to sixty metres, to
	# keep a fold in the road from catching the rounds -- which put the mark
	# underground, and from a muzzle lower than the eye every round aimed at
	# the road came down metres short of it. Lying down that is every shot.
	# The fold is dealt with below, for what it is.
	var seen: float = Firearm.sight_range(start, look, 600.0)
	var mark: Vector3 = start + look * seen
	# And held up for the drop over that distance, so it lands where it is
	# pointed. Laid flat on the crosshair, a rifle round at three hundred
	# metres is half a metre low, and along a line skimming the road that is
	# a hundred metres short.
	# Only for something actually there: with nothing under the crosshair the
	# "mark" is just how far the look was taken, and holding up for six
	# hundred metres lobs the round over the line of sight on the way.
	# What it falls under: a rifle round all of it, a rocket a little (its
	# motor holds it up), a guided missile none. The launcher table calls the
	# AT4 a "rocket" -- this asked for "law" and so held an AT4 up for a
	# rifle round's drop.
	var launcher := String(g.get("launcher", ""))
	var fall: float = 3.0 if launcher == "rocket" else (0.0 if launcher == "sam" else 9.81)
	var speed: float = float(g["muzzle"])
	# rounds and the 40 mm fly the whole model; the AT4's motor holds it up
	var air_k: float = Firearm.drag_of(g) if launcher != "rocket" else -1.0
	# A rifle is sighted in, not ranged. It used to be laid for the drop over
	# however far it was to whatever was under the crosshair -- and people
	# are not in that answer, only walls and ground: a man in a doorway with a
	# wall three hundred metres behind him had every round laid for three
	# hundred metres and sent over his head. Now the round crosses the line of
	# sight at the weapon's zero, and the turrets move it from there: closer
	# than the zero it is a touch high, further out it drops, and the drop is
	# the shooter's to hold over or dial. Launchers range themselves.
	var zeroed: bool = launcher == ""
	var lay_at: Vector3 = mark
	var sky: bool = seen >= 599.0
	if zeroed:
		lay_at = start + look * w.zero_of(g)
		sky = false
	var aim: Vector3 = _lay(from, lay_at, speed, fall, sky, air_k)
	# a grenade launcher is laid well above the line of sight at range
	var off_line: float = 0.0 if launcher == "gl" else 0.5
	if mark.distance_to(from) < 1.6 or aim.dot(look) < off_line:
		aim = look
	elif _fouled(from, mark) and not _fouled(start, mark):
		# The muzzle cannot see what the eye can: a hump in the road a few
		# metres in front of a man lying down, the sill a rifle is rested on,
		# or anything below an over-the-shoulder view. The round goes from the
		# line of sight, which on the screen is clear all the way, instead of
		# into the ground in front of him.
		from = start
		aim = _lay(start, lay_at, speed, fall, sky, air_k)
	if zeroed:
		aim = w.turrets(aim, look, w.kit_idx)
	var quiet: bool = w.is_quiet()
	if g.has("launcher"):
		if String(g["launcher"]) == "sam":
			if not is_instance_valid(w.lock_target) or w.lock_t < Walker.LOCK_TIME:
				# no tone, no shot: it will not leave the tube without a lock
				w.ammo += 1
				w._rounds[w.kit_idx] = w.ammo
				w._shot_cd = 0.3
				Sfx.play_ui(world, "dry", -6.0)
				Sim.report("no lock — hold the sights on an aircraft", Sim.Ev.BAD)
				return
			Firearm.sam(world, w, w.side, from, look, w.lock_target)
			w.lock_t = 0.0
		elif String(g["launcher"]) == "gl":
			Firearm.grenade40(world, w, w.side, g, from, aim)
		else:
			Firearm.rocket(world, w, w.side, g, from, aim)
	else:
		# Inside an aircraft the round has the aircraft's speed as well as its
		# own. Where it goes from there -- out over the ramp, or into the
		# inside of the fuselage -- is the round's business: `Effects.hull_hit`.
		var carrier_vel := Vector3.ZERO
		if w.frame != null and is_instance_valid(w.frame_owner):
			carrier_vel = w.frame_owner.get_meta("net_vel") if w.frame_owner.has_meta("net_vel") \
				else (w.frame_owner.get("linear_velocity") if "linear_velocity" in w.frame_owner else Vector3.ZERO)
		Firearm.fire(world, w, w.side, g, from, aim, s, 1.0, quiet, carrier_vel)
		# and on everyone else's screen: the flash, the report and the round
		var nl: Variant = world.get("net") if world != null else null
		if nl != null and is_instance_valid(nl) and (nl as NetLink).active:
			(nl as NetLink).send_foot_shot(from, aim, String(g["id"]), quiet, carrier_vel)
	if is_instance_valid(w.arena) and w.arena.has_method("heard"):
		# a suppressed shot is heard by whoever is in the same yard, no further
		w.arena.heard(from, w.side, 14.0 if quiet else 75.0)
	# The kick: most of it comes back on its own, some of it you have to pull
	# down yourself, and it never climbs quite straight.
	var k: float = float(g["kick"]) * (1.0 - 0.35 * w._ads) \
		* (0.55 if w.prone else (0.8 if w.crouching else 1.0))
	# rested on something, the something takes most of it
	if w.mounted:
		k *= 0.45
	w.pitch = minf(w.pitch + k * 0.45, 1.35)
	w._recoil = minf(w._recoil + k * 0.9, 0.12)
	w.yaw += randf_range(-1.0, 1.0) * float(g["side"]) * (1.0 - 0.3 * w._ads) * (0.4 if w.mounted else 1.0)
	w._bloom = minf(w._bloom + float(g["hip"]) * 0.22, float(g["hip"]) * 1.6)
	w.body.kick(clampf(float(g["kick"]) * 34.0, 0.3, 1.5))
	# Working the action between shots: a pump, a bolt, or nothing -- a drum
	# launcher is loaded one round at a time but fires straight off the next.
	var cyc := String(g.get("cycle", "pump" if g.get("shells", false) else ""))
	if cyc != "":
		_cycle_snd = cyc
		w._pump_in = 0.24 if cyc == "pump" else 0.40

## The mortar is worked from the ground: the first pull sets it up where he
## stands (stand still for it), the sights button -- or a pull with nothing
## plotted -- opens the map to lay it on a fire mission, and each pull after
## that puts a round down the tube onto the mission. Moving off it, or taking
## up another weapon, packs it up.
func _work_mortar(delta: float, g: Dictionary, edge: bool) -> void:
	var world := w.get_tree().current_scene
	var moving: bool = Vector2(w.vel.x, w.vel.z).length() > 0.8 or not w.on_floor or w.frame != null
	if not is_instance_valid(tube):
		tube = null
		if edge:
			if moving:
				Sim.report("mortar: stand still to set it up", Sim.Ev.BAD)
			else:
				tube = MortarTube.new()
				tube.spec = g
				world.add_child(tube)
				var fwd := Vector3(-sin(w.yaw), 0.0, -cos(w.yaw))
				var at: Vector3 = w.global_position + fwd * 0.7
				tube.global_position = Vector3(at.x, w.global_position.y, at.z)
				if is_instance_valid(w.body.gun_node):
					w.body.gun_node.visible = false
				Sfx.play_ui(world, "cloth", -6.0, 0.8)
				Sim.report("setting up the mortar…", Sim.Ev.INFO)
		return
	if moving or Vector2(tube.global_position.x - w.global_position.x,
			tube.global_position.z - w.global_position.z).length() > MortarTube.STAY:
		_pack_tube()
		Sim.report("mortar packed up", Sim.Ev.INFO)
		return
	if tube.work(delta):
		Sfx.play_ui(world, "clink", -8.0, 0.9)
		Sim.report("mortar ready — RMB to plot a fire mission on the map", Sim.Ev.GOOD)
	if not tube.ready_to_fire():
		return
	if Sim.tapped(&"ads") or (edge and tube.mission == Vector3.INF):
		_plot_mission()
		return
	if not edge or w._shot_cd > 0.0 or tube.mission == Vector3.INF:
		return
	if w.ammo <= 0:
		Sfx.play_ui(world, "dry", -6.0)
		if w.spare > 0:
			_begin_reload(g)
		return
	w._shot_cd = float(g["cd"])
	w.ammo -= 1
	w._rounds[w.kit_idx] = w.ammo
	var mr: MortarRound = tube.fire(w, w.arena)
	world.add_child(mr)
	if Sim.net != null:
		Sim.net.launches.share_round(mr)
	Sfx.play_at(world, "thump", mr.from, 2.0, 0.9, 1500.0)
	Effects.dust(world, tube.global_position, 1.2)
	if is_instance_valid(w.arena) and w.arena.has_method("heard"):
		w.arena.heard(mr.from, w.side, 90.0)
	Sim.report("round out — %d m, %.0f seconds" % [int(Vector2(tube.mission.x - mr.from.x,
		tube.mission.z - mr.from.z).length()), mr.flight], Sim.Ev.INFO)

## Open the map to lay the tube on a fire mission: a line from the tube to
## the cursor with the range on it, and a click where it is to go.
func _plot_mission() -> void:
	var world := w.get_tree().current_scene
	var map: Variant = world.get("map") if world != null else null
	if map == null or not is_instance_valid(map) or not is_instance_valid(tube):
		return
	var t: MortarTube = tube
	(map as MapView).pick("FIRE MISSION", func(p: Vector3):
		if not is_instance_valid(t):
			return
		var why: String = t.cannot_reach(p)
		if why != "":
			Sim.report("mortar: " + why, Sim.Ev.BAD)
			return
		t.lay_on(p)
		Sim.report("fire mission laid — %d m. Fire when ready" % int(Vector2(p.x - t.global_position.x,
			p.z - t.global_position.z).length()), Sim.Ev.GOOD))
	# measured from the tube, not from wherever the map's last line began
	(map as MapView).pick_from = tube.global_position

## Take the mortar back up off the ground.
func _pack_tube() -> void:
	if is_instance_valid(tube):
		tube.queue_free()
	tube = null
	if is_instance_valid(w.body) and is_instance_valid(w.body.gun_node):
		w.body.gun_node.visible = true

## The seeker. With the missile up and the sights on something that flies,
## it takes a moment to settle; look away and it lets go.
## Which way to send a round so it comes down on the mark: the arc for its
## speed and what it falls under, or as far as it will go toward the mark if
## the mark is out of reach. With nothing under the crosshair there is no
## distance to allow for, and it goes the way it is pointed.
func _lay(from: Vector3, mark: Vector3, speed: float, fall: float, open_sky: bool,
		k := -1.0) -> Vector3:
	if open_sky or fall <= 0.0:
		return (mark - from).normalized()
	var d: Vector3 = Firearm.lob(from, mark, speed, fall)
	if d != Vector3.ZERO:
		if k >= 0.0:
			# The vacuum arc is the first guess; the round flies through air on
			# a turning planet, so the guess is corrected against that until it
			# comes down on the mark. Inside the first thirty metres the two are
			# the same and this costs a step or two.
			var sol: Dictionary = Ballistics.solve(from, mark, speed, k, d)
			if not sol.is_empty():
				return sol["dir"]
		return d
	var h := Vector3(mark.x - from.x, 0.0, mark.z - from.z)
	return (h.normalized() + Vector3.UP).normalized() if h.length() > 0.01 \
		else (mark - from).normalized()

## Whether something stands between two points: a wall or a prop anywhere
## along it, or the ground in the first stretch of it, where a line from a man
## lying down is closest to the road. The far end is the mark itself, which is
## on whatever it hit, so the last few per cent do not count.
func _fouled(a: Vector3, b: Vector3) -> bool:
	var span: float = a.distance_to(b)
	if span < 0.5:
		return false
	if Obstacles.segment(a, b) < 0.97:
		return true
	var dir: Vector3 = (b - a) / span
	var near: float = minf(span * 0.97, 25.0)
	var s := 0.4
	while s < near:
		var p: Vector3 = a + dir * s
		if p.y < Sim.height_at(p.x, p.z):
			return true
		s += 0.5
	return false

func _seek(delta: float, g: Dictionary) -> void:
	if String(g.get("launcher", "")) != "sam" or w._ads < 0.6 or w.ammo <= 0:
		w.lock_target = null
		w.lock_t = 0.0
		return
	var eye := w._aim_xf.origin
	var look := -w._aim_xf.basis.z
	var best: Node3D = null
	var best_a := deg_to_rad(Walker.SEEK_CONE)
	Sim.hit_scan()
	for i in Sim.hit_nodes.size():
		if Sim.hit_team[i] == w.side:
			continue
		var n: Variant = Sim.hit_nodes[i]
		if not is_instance_valid(n) or not (n is Aircraft) or not n.is_alive():
			continue
		var to: Vector3 = (n as Node3D).global_position - eye
		# as far as the round can fly, and a little short of it
		if to.length() > float(WeaponSpec.get_spec("manpads")["range"]) * 0.95 or to.length() < 60.0:
			continue
		var ang: float = look.angle_to(to)
		if ang < best_a and Firearm.can_see(eye, (n as Node3D).global_position) \
				and Sim.line_of_sight(eye, (n as Node3D).global_position):
			best_a = ang
			best = n
	if best != w.lock_target:
		w.lock_t = 0.0
	w.lock_target = best
	if best != null:
		var before := w.lock_t
		w.lock_t += delta
		if before < Walker.LOCK_TIME and w.lock_t >= Walker.LOCK_TIME:
			Sfx.play_ui(w.get_tree().current_scene, "killmark", -6.0, 1.4)
		# The seeker's tone: a slow tick while it is working on something,
		# quick and higher once it has it. The eye is on the aeroplane, not on
		# the words under the ring, and this is what says "now".
		_tone_t -= delta
		if _tone_t <= 0.0:
			var has_it: bool = w.lock_t >= Walker.LOCK_TIME
			_tone_t = 0.27 if has_it else 0.6
			Sfx.play_ui(w.get_tree().current_scene, "beep", -14.0 if has_it else -20.0,
				2.0 if has_it else 1.0)
	else:
		_tone_t = 0.0

func _begin_reload(g: Dictionary) -> void:
	w._reload_span = maxf(float(g["reload"]), 0.05)
	w.reloading = w._reload_span
	_reload_mark = 0
	_reload_empty = w.ammo <= 0
	w._pump_in = 0.0

## A reload is something the hands do in stages, each of which you can hear.
func _work_reload(delta: float, g: Dictionary, trigger_edge: bool) -> void:
	var world := w.get_tree().current_scene
	var at := w.global_position + Vector3(0, 1.35, 0)
	w.reloading -= delta
	var p: float = 1.0 - clampf(w.reloading / w._reload_span, 0.0, 1.0)
	if g.get("shells", false):
		# one at a time into the tube, and the trigger breaks off the loading
		if _reload_mark == 0 and p > 0.55:
			_reload_mark = 1
			w.ammo += 1
			w.spare -= 1
			Sfx.play_at(world, "shell", at, -9.0, randf_range(0.95, 1.1), 40.0)
		if w.reloading <= 0.0:
			w._rounds[w.kit_idx] = w.ammo
			w._spare[w.kit_idx] = w.spare
			if w.ammo < int(g["mag"]) and w.spare > 0 and not trigger_edge and not w._trigger():
				w.reloading = w._reload_span
				_reload_mark = 0
			else:
				w.reloading = 0.0
				if _reload_empty and String(g.get("cycle", "pump")) != "":
					Sfx.play_at(world, String(g.get("cycle", "pump")), at, -8.0, 1.0, 60.0)
					w._shot_cd = 0.3
		return
	if _reload_mark == 0 and p > 0.22:
		_reload_mark = 1
		Sfx.play_at(world, "mag_out", at, -9.0, randf_range(0.95, 1.05), 40.0)
	elif _reload_mark == 1 and p > 0.66:
		_reload_mark = 2
		Sfx.play_at(world, "mag_in", at, -8.0, randf_range(0.95, 1.05), 40.0)
	elif _reload_mark == 2 and p > 0.86:
		_reload_mark = 3
		if _reload_empty:
			Sfx.play_at(world, String(g["work"]), at, -8.0, randf_range(0.95, 1.05), 40.0)
	if w.reloading <= 0.0:
		w.reloading = 0.0
		var take: int = mini(int(g["mag"]) - w.ammo, w.spare)
		w.ammo += take
		w.spare -= take
		w._rounds[w.kit_idx] = w.ammo
		w._spare[w.kit_idx] = w.spare

func _throw() -> void:
	if _throw_flash:
		w.flashes -= 1
	else:
		w.grenades -= 1
	var world := w.get_tree().current_scene
	var look := -w._aim_xf.basis.z
	var f := Firearm.Frag.new()
	if _throw_flash:
		# a short fuse: it is meant to go off as it arrives, not after
		f.flash = true
		f.fuse = 1.7
	f.team = w.side
	f.thrower = w
	# A good overarm throw: eighteen metres a second with some loft on it --
	# about twenty metres thrown level, thirty-odd at a slight lob, and a little
	# over forty at best, which is what a strong arm manages. It fell sixteen
	# metres out at best under a heavy gravity, short of the next doorway.
	f.vel = look * 18.0 + Vector3(0, 4.0, 0) + Vector3(w.vel.x, 0, w.vel.z) * 0.6
	world.add_child(f)
	# out of the hand that threw it
	var hand: Vector3 = w.body.fore_l.global_transform * Vector3(0, -Pilot.ARM_2, 0)
	f.global_position = hand if hand.distance_to(w.body.eye_pos()) < 1.2 \
		else w.body.eye_pos() + look * 0.5
	if Sim.net != null:
		Sim.net.launches.share_round(f)
	Sfx.play_at(world, "cloth", f.global_position, -8.0, 1.3, 30.0)

## A round of yours landed.
func hit_confirm(head: bool, killed: bool) -> void:
	w.hit_t = 0.22
	w.hit_head = head
	var world := w.get_tree().current_scene
	if killed:
		w.kill_t = 0.6
		Sfx.play_ui(world, "killmark", -9.0)
	else:
		Sfx.play_ui(world, "hitmark", -9.0, 1.25 if head else 1.0)

## The field of view through the sights of `g`, with a variable scope's
## power worked in.
func scope_fov(g: Dictionary) -> float:
	return float(g["fov"]) / clampf(float(w.scope_mag.get(w.kit_idx, 1.0)), 1.0,
		maxf(float(g.get("zoom_max", 1.0)), 1.0))

## True while looking through glass rather than over iron.
func scoped() -> bool:
	return not w.third and w._ads > 0.9 and w.gun_spec().get("scope", false)

# ------------------------------------------------------------------ the figure
