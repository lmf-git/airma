class_name FootHud
extends RefCounted
## The head-up picture for a man on foot: the chevrons over his own side, the
## glasses and the scope, the crosshair, the rounds left, the hurt. Split out of
## `hud.gd`, which draws it through this; every draw call is the HUD's own.

var h: HUD

func _init(hud: HUD) -> void:
	h = hud

## What a man on foot needs in front of him: where the rounds will go, what
## is left to send, and what is being done to him.
func draw() -> void:
	var vp := h.get_viewport_rect().size
	var c := vp * 0.5
	var w: Walker = h.walker as Walker
	var g: Dictionary = w.gun_spec()
	var eye: Camera3D = w.cam

	# Whose side everyone is on. Uniforms do it up close; across a street in
	# bad light a chevron over your own people does it better.
	if is_instance_valid(eye) and eye.current:
		for n in h.get_tree().get_nodes_in_group("infantry"):
			var sd := n as Soldier
			if sd == null or sd.team != w.side or not sd.is_alive():
				continue
			var at: Vector3 = sd.global_position + Vector3(0, 2.05, 0)
			if eye.is_position_behind(at):
				continue
			var far: float = eye.global_position.distance_to(at)
			var sp: Vector2 = eye.unproject_position(at)
			# A man right at the camera plane projects to infinity, or to
			# nothing a triangle can be made of, and the fill says so.
			if not sp.is_finite() or absf(sp.x) > 1.0e5 or absf(sp.y) > 1.0e5 or far < 0.3:
				continue
			var a: float = clampf(1.15 - far / 160.0, 0.25, 0.9)
			var blue := Color(0.35, 0.72, 1.0, a)
			h.draw_colored_polygon(PackedVector2Array([sp + Vector2(-5, -8), sp + Vector2(5, -8),
				sp + Vector2(0, 0)]), blue)
			if far < 40.0:
				h._txt(Vector2(sp.x - 60.0, sp.y - 12.0), sd.callsign, 11, blue,
					HORIZONTAL_ALIGNMENT_CENTER, 120.0)

	if not (is_instance_valid(eye) and eye.current):
		# Riding a round on the weapon camera: his sight is not what is on
		# the screen, and a scope tube or a crosshair over the ride marks
		# nothing.
		pass
	elif w.glassing():
		# Field glasses: two tubes side by side, and what is outside them is
		# the inside of them. The outline is the two circles run together.
		var br: float = minf(vp.y * 0.46, vp.x * 0.31)
		var off: float = br * 0.5
		var cut: float = acos(off / br)
		var bdark := Color(0, 0, 0, 1)
		h.draw_rect(Rect2(0, 0, c.x - off - br, vp.y), bdark)
		h.draw_rect(Rect2(c.x + off + br, 0, vp.x - c.x - off - br, vp.y), bdark)
		var top := PackedVector2Array([Vector2(c.x - off - br, 0.0)])
		var bot := PackedVector2Array([Vector2(c.x - off - br, vp.y)])
		var rim := PackedVector2Array()
		for i in 25:
			var ta: float = lerpf(PI, TAU - cut, float(i) / 24.0)
			var q := Vector2(cos(ta), sin(ta)) * br
			top.append(c + Vector2(-off, 0) + q)
			bot.append(c + Vector2(-off, 0) + Vector2(q.x, -q.y))
		# from 1: the first point of this arc is the last of the other, and a
		# polygon with the same corner twice running does not triangulate
		for i in range(1, 25):
			var tb: float = lerpf(PI + cut, TAU, float(i) / 24.0)
			var q2 := Vector2(cos(tb), sin(tb)) * br
			top.append(c + Vector2(off, 0) + q2)
			bot.append(c + Vector2(off, 0) + Vector2(q2.x, -q2.y))
		rim.append_array(top.slice(1))
		var back := bot.slice(1)
		back.reverse()
		rim.append_array(back)
		rim.append(rim[0])
		top.append(Vector2(c.x + off + br, 0.0))
		bot.append(Vector2(c.x + off + br, vp.y))
		h.draw_colored_polygon(top, bdark)
		h.draw_colored_polygon(bot, bdark)
		h.draw_polyline(rim, bdark, 7.0, true)
		# a mil scale across the middle, and a short post under it
		var bink := Color(0.03, 0.03, 0.03, 0.9)
		h.draw_line(c + Vector2(-br * 0.5, 0), c + Vector2(-10, 0), bink, 1.4)
		h.draw_line(c + Vector2(10, 0), c + Vector2(br * 0.5, 0), bink, 1.4)
		h.draw_line(c + Vector2(0, 10), c + Vector2(0, br * 0.22), bink, 1.4)
		for k in range(-5, 6):
			if k == 0:
				continue
			var tx: float = float(k) * br * 0.1
			var th: float = 9.0 if k % 5 == 0 else 5.0
			h.draw_line(c + Vector2(tx, -th), c + Vector2(tx, th), bink, 1.2)
		var rng: float = w.glass_range()
		var brg: int = int(round(fposmod(-rad_to_deg(w.yaw), 360.0))) % 360
		h._txt(Vector2(c.x - 150.0, c.y + br * 0.62), "%03d°   %s" % [brg,
			("%d m" % int(round(rng))) if rng >= 0.0 else "--- m"], 16,
			Color(0.75, 1.0, 0.8, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	elif w.scoped():
		# through the glass: everything outside the tube is the inside of it.
		# A 2x shows most of the screen, a prism a little less, a long scope
		# least of all.
		var reticle := String(g.get("reticle", "cross"))
		var r: float = vp.y * (0.49 if reticle == "ring" else (0.43 if reticle == "chevron" else 0.46))
		var dark := Color(0, 0, 0, 1)
		h.draw_rect(Rect2(0, 0, c.x - r, vp.y), dark)
		h.draw_rect(Rect2(c.x + r, 0, vp.x - c.x - r, vp.y), dark)
		# The corners between the circle and the square it sits in, as two
		# shapes: above the glass and below it. It was a strip per segment of
		# the rim down to the nearer edge, and the two strips that crossed the
		# middle went up on one side and down on the other -- a bow tie, which
		# the polygon fill cannot triangulate, and said so every frame.
		var above := PackedVector2Array([Vector2(c.x - r, 0.0)])
		var below := PackedVector2Array([Vector2(c.x + r, vp.y)])
		for i in 33:
			var ta: float = PI + PI * float(i) / 32.0
			above.append(c + Vector2(cos(ta), sin(ta)) * r)
			var tb: float = PI * float(i) / 32.0
			below.append(c + Vector2(cos(tb), sin(tb)) * r)
		above.append(Vector2(c.x + r, 0.0))
		below.append(Vector2(c.x - r, vp.y))
		h.draw_colored_polygon(above, dark)
		h.draw_colored_polygon(below, dark)
		h.draw_arc(c, r, 0, TAU, 64, Color(0, 0, 0, 1), 6.0)
		var ink := Color(0.03, 0.03, 0.03, 0.95)
		if reticle == "ring":
			# a lit ring and a dot, and nothing else in the way
			var lit := Color(1.0, 0.18, 0.10, 0.9)
			h.draw_arc(c, 34.0, 0, TAU, 48, lit, 1.6)
			h.draw_circle(c, 2.0, lit)
		elif reticle == "chevron":
			# the prism's chevron, lit amber, on a post, with the drop below it
			var amb := Color(1.0, 0.62, 0.12, 0.95)
			h.draw_line(c + Vector2(-9, 9), c, amb, 2.2)
			h.draw_line(c, c + Vector2(9, 9), amb, 2.2)
			h.draw_line(c + Vector2(0, 14), c + Vector2(0, r * 0.55), ink, 1.6)
			for k in range(1, 5):
				var y: float = 14.0 + k * 18.0
				var hw: float = 10.0 - k * 1.5
				h.draw_line(c + Vector2(-hw, y), c + Vector2(hw, y), ink, 1.2)
			h.draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.55, 0), ink, 1.4)
			h.draw_line(c + Vector2(r * 0.55, 0), c + Vector2(r, 0), ink, 1.4)
		else:
			h.draw_line(c + Vector2(-r, 0), c + Vector2(-14, 0), ink, 2.0)
			h.draw_line(c + Vector2(14, 0), c + Vector2(r, 0), ink, 2.0)
			h.draw_line(c + Vector2(0, 14), c + Vector2(0, r), ink, 2.0)
			h.draw_line(c + Vector2(0, -r), c + Vector2(0, -14), ink, 1.0)
			for k in range(1, 5):
				h.draw_line(c + Vector2(-5, k * 22.0), c + Vector2(5, k * 22.0), ink, 1.0)
			h.draw_circle(c, 1.4, Color(0.9, 0.1, 0.05, 0.9))
	else:
		# Four ticks that open as the weapon wanders. Through the sights in
		# first person the sights are the mark -- irons, a dot, a holo -- and
		# ticks painted over them only hid what they were laid on. It went only
		# for a red dot; now it fades as any weapon comes up to the eye. Over
		# the shoulder there is nothing to look through, so it stays.
		var fade: float = 1.0 if w.third else clampf(1.0 - w._ads * 1.6, 0.0, 1.0)
		if fade > 0.01:
			var px: float = vp.y * 0.5 / tan(deg_to_rad(eye.fov * 0.5)) if is_instance_valid(eye) else 600.0
			var gap: float = clampf(w.spread_now * px, 3.0, 90.0) + 3.0
			var col := Color(1, 1, 1, (0.82 if w.reloading <= 0.0 else 0.3) * fade)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				h.draw_line(c + d * gap, c + d * (gap + 7.0), Color(0, 0, 0, 0.5 * fade), 3.0)
				h.draw_line(c + d * gap, c + d * (gap + 7.0), col, 1.4)
			h.draw_circle(c, 1.2, col)

	# The missile's sight: a ring the size of what the seeker can see, and
	# what the seeker is doing about it.
	#
	# All there was to aim a Stinger by was the tube itself and a box that
	# appeared on an aeroplane once the seeker had already found it -- nothing
	# said where to point to make that happen, how far along the lock was, or
	# that the thing would not fire without one. The ring is the seeker's
	# cone drawn to scale, so an aeroplane inside it is one it is looking at;
	# it fills round as the lock builds, and goes red and steady with it.
	var sam: bool = String(g.get("launcher", "")) == "sam"
	if sam and w._ads > 0.5 and is_instance_valid(eye) and eye.current:
		var px_s: float = vp.y * 0.5 / tan(deg_to_rad(eye.fov * 0.5))
		var ring: float = clampf(tan(deg_to_rad(w.SEEK_CONE)) * px_s, 40.0, vp.y * 0.46)
		var has: bool = is_instance_valid(w.lock_target)
		var got: bool = has and w.lock_t >= w.LOCK_TIME
		var sc := Color(0.55, 1.0, 0.62, 0.85)
		if got:
			sc = Color(1.0, 0.22, 0.16, 0.95)
		elif has:
			sc = Color(1.0, 0.74, 0.2, 0.95)
		var fade_s: float = clampf((w._ads - 0.5) * 4.0, 0.0, 1.0)
		sc.a *= fade_s
		var under := Color(0, 0, 0, 0.45 * fade_s)
		h.draw_arc(c, ring, 0.0, TAU, 72, under, 3.6)
		h.draw_arc(c, ring, 0.0, TAU, 72, sc, 1.6)
		# ticks at the quarters, and a pip to lay on it with
		for d4 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			h.draw_line(c + d4 * (ring - 10.0), c + d4 * (ring + 10.0), sc, 1.6)
			h.draw_line(c + d4 * 6.0, c + d4 * 16.0, sc, 1.4)
		h.draw_circle(c, 1.6, sc)
		if has and not got:
			# the lock, filling clockwise from the top
			var f: float = clampf(w.lock_t / w.LOCK_TIME, 0.0, 1.0)
			h.draw_arc(c, ring + 7.0, -PI * 0.5, -PI * 0.5 + TAU * f, 48, sc, 3.0)
		elif got:
			h.draw_arc(c, ring + 7.0, 0.0, TAU, 72, sc, 3.0)
		var word := "NO TARGET"
		if w.ammo <= 0:
			word = "TUBE EMPTY"
		elif got:
			word = "LOCKED — FIRE" if fmod(h._t, 0.3) < 0.2 else ""
		elif has:
			word = "SEEKING"
		h._txt(Vector2(c.x - 120.0, c.y + ring + 30.0), word, 16, sc,
			HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	# the seeker: a box on what it is looking at, closed when it has it
	if is_instance_valid(w.lock_target) and is_instance_valid(eye) \
			and not eye.is_position_behind(w.lock_target.global_position):
		var tgt_at: Vector3 = w.lock_target.global_position
		var lp: Vector2 = eye.unproject_position(tgt_at)
		var locked: bool = w.lock_t >= w.LOCK_TIME
		var lc := h.RED if locked else h.AMBER
		var lh: float = 26.0 if locked else lerpf(60.0, 26.0, clampf(w.lock_t / w.LOCK_TIME, 0.0, 1.0))
		if locked:
			# a diamond on it, and a line from the pip so it can be followed
			h.draw_polyline(PackedVector2Array([lp + Vector2(0, -lh), lp + Vector2(lh, 0),
				lp + Vector2(0, lh), lp + Vector2(-lh, 0), lp + Vector2(0, -lh)]), lc, 2.2)
			if lp.distance_to(c) > lh + 8.0:
				h.draw_line(c + (lp - c).normalized() * 8.0,
					lp - (lp - c).normalized() * lh, Color(lc.r, lc.g, lc.b, 0.5), 1.2)
		else:
			h._box(Rect2(lp.x - lh, lp.y - lh, lh * 2.0, lh * 2.0), lc, 2.0)
		h._txt(Vector2(lp.x - 80.0, lp.y + lh + 16.0), "%s  %.1f km" % [
			"LOCK" if locked else "SEEKING",
			eye.global_position.distance_to(tgt_at) * 0.001], 14, lc,
			HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	# a round of yours landing
	if w.hit_t > 0.0:
		var hc := Color(1.0, 0.25, 0.2, 1.0) if (w.kill_t > 0.0 or w.hit_head) else Color(1, 1, 1, 1)
		hc.a = clampf(w.hit_t / 0.22, 0.0, 1.0)
		var o: float = 7.0 + (1.0 - hc.a) * 4.0
		for d2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			h.draw_line(c + d2 * o, c + d2 * (o + 8.0), hc, 2.2)
	# and one of theirs: an arc on the side it came from
	if w.hurt_t > 0.0 and is_instance_valid(eye):
		var to: Vector3 = w.hurt_from - w.global_position
		var bearing: float = atan2(to.x, -to.z) + w.yaw
		var ha: float = clampf(w.hurt_t, 0.0, 1.0) * 0.85
		h.draw_arc(c, 120.0, bearing - PI * 0.5 - 0.32, bearing - PI * 0.5 + 0.32, 14,
			Color(1.0, 0.12, 0.08, ha), 7.0)
	# hurt: the edges of the world close in
	var blood: float = clampf(1.0 - w.health / 60.0, 0.0, 1.0)
	if blood > 0.0:
		var edge := Color(0.55, 0.0, 0.0, 0.34 * blood)
		var band: float = vp.y * 0.16
		h.draw_rect(Rect2(0, 0, vp.x, band), edge)
		h.draw_rect(Rect2(0, vp.y - band, vp.x, band), edge)
		h.draw_rect(Rect2(0, band, band, vp.y - band * 2.0), edge)
		h.draw_rect(Rect2(vp.x - band, band, band, vp.y - band * 2.0), edge)
	# pinned down: the edges go dark and the middle is all there is
	if w.suppression > 0.02:
		var dark := Color(0.0, 0.0, 0.0, 0.5 * w.suppression)
		var rim: float = vp.y * (0.10 + 0.14 * w.suppression)
		h.draw_rect(Rect2(0, 0, vp.x, rim), dark)
		h.draw_rect(Rect2(0, vp.y - rim, vp.x, rim), dark)
		h.draw_rect(Rect2(0, rim, rim, vp.y - rim * 2.0), dark)
		h.draw_rect(Rect2(vp.x - rim, rim, rim, vp.y - rim * 2.0), dark)
		h.draw_rect(Rect2(0, 0, vp.x, rim * 0.5), dark)
		h.draw_rect(Rect2(0, vp.y - rim * 0.5, vp.x, rim * 0.5), dark)
		h.draw_rect(Rect2(0, rim * 0.5, rim * 0.5, vp.y - rim), dark)
		h.draw_rect(Rect2(vp.x - rim * 0.5, rim * 0.5, rim * 0.5, vp.y - rim), dark)
	# a stun grenade: nothing but white, and then the world coming back
	var dazed: float = w.flash_left()
	if dazed > 0.0:
		var back: float = clampf(dazed / maxf(w.flash_span * 0.55, 0.4), 0.0, 1.0)
		h.draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 1.0, 1.0, back * back * (3.0 - 2.0 * back)))

	var p: String = w.prompt()
	if p != "":
		var bw := 420.0
		h.draw_rect(Rect2(c.x - bw * 0.5, c.y + 90.0, bw, 40.0), Color(0.02, 0.05, 0.07, 0.6), true)
		h._box(Rect2(c.x - bw * 0.5, c.y + 90.0, bw, 40.0), h.AMBER, 1.4)
		h._txt(Vector2(c.x - bw * 0.5, c.y + 116.0), p, 19, h.AMBER, HORIZONTAL_ALIGNMENT_CENTER, bw)

	# what is in the hands, bottom right where the weapon is
	var rel: bool = w.reloading > 0.0
	var low: bool = w.ammo <= maxi(int(float(g["mag"]) * 0.2), 1)
	var modes: Array = Walker.modes_of(g)
	h._txt(Vector2(vp.x - 330.0, vp.y - 118.0), String(g["name"])
		+ ("  · SUPPRESSED" if w.is_quiet() else "")
		+ ("  · %s (V)" % w.mode_now().to_upper() if modes.size() > 1 else ""), 15,
		Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	# rested, and the breath he is holding
	if w._ads > 0.5:
		var cx: float = vp.x * 0.5
		var cy: float = vp.y * 0.5 + 70.0
		if w.mounted:
			h._txt(Vector2(cx - 60.0, cy), "RESTED", 12, Color(0.6, 0.9, 0.6),
				HORIZONTAL_ALIGNMENT_CENTER, 120.0)
		if w.breath < 0.999 or w.steadying:
			var bw := 90.0
			var col: Color = h.RED if w._gasp else (Color(0.85, 0.92, 1.0) if w.steadying else Color(0.6, 0.65, 0.7))
			h.draw_rect(Rect2(cx - bw * 0.5, cy + 16.0, bw * w.breath, 3.0), col)
			h._box(Rect2(cx - bw * 0.5, cy + 16.0, bw, 3.0), col, 1.0)
	h._txt(Vector2(vp.x - 330.0, vp.y - 78.0), "%d" % w.ammo, 40,
		h.RED if (low or rel) else h.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 220.0)
	h._txt(Vector2(vp.x - 104.0, vp.y - 78.0), "/ %d" % w.spare, 20,
		Color(0.75, 0.8, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 90.0)
	if rel:
		h._txt(Vector2(vp.x - 330.0, vp.y - 54.0), "RELOADING", 14, h.AMBER,
			HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	elif w.ammo == 0:
		h._txt(Vector2(vp.x - 330.0, vp.y - 54.0), "EMPTY — R" if w.spare > 0 else "OUT — SWITCH WEAPON",
			14, h.RED, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	h._txt(Vector2(vp.x - 330.0, vp.y - 32.0), "GRENADES %d   FLASH %d" % [w.grenades, w.flashes], 14,
		Color(0.75, 0.8, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	# the sights: where it is zeroed and what is dialled on, always while on
	# them, and otherwise only once something has been dialled
	if not g.has("launcher"):
		var el: float = float(w.elev_mil.get(w.kit_idx, 0.0))
		var wd: float = float(w.wind_mil.get(w.kit_idx, 0.0))
		if w._ads > 0.5 or el != 0.0 or wd != 0.0:
			h._txt(Vector2(vp.x - 330.0, vp.y - 138.0), "ZERO %d m   ELEV %+.1f   WIND %s%.1f mil   ↑↓←→" % [
				int(w.zero_of(g)), el, "R " if wd > 0.0 else ("L " if wd < 0.0 else ""), absf(wd)],
				13, h.AMBER if (el != 0.0 or wd != 0.0) else Color(0.75, 0.8, 0.85),
				HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		# a variable scope says what power it is on, in the scope's own terms
		if w._ads > 0.5 and float(g.get("zoom_max", 1.0)) > 1.0:
			h._txt(Vector2(vp.x - 330.0, vp.y - 156.0), "%.1fx   WHEEL ZOOM" % (Walker.BASE_FOV / w.scope_fov(g)),
				13, Color(0.75, 0.8, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
	# the rack: which number is which
	for i in w.slots.size():
		var on: bool = i == w.slot
		h._txt(Vector2(vp.x - 330.0, vp.y - 196.0 + i * 18.0), "%d  %s" % [i + 1,
			String(w.spec_of(int(w.slots[i]))["name"])], 13,
			h.AMBER if on else Color(0.55, 0.6, 0.65), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)

	var hb := 220.0
	var frac: float = clampf(w.health / 100.0, 0.0, 1.0)
	var hcol := h.RED if w.health < 40.0 else h.GREEN
	h._box(Rect2(26, vp.y - 74.0, hb, 12), hcol, 1.2)
	h.draw_rect(Rect2(27, vp.y - 73.0, (hb - 2.0) * frac, 10), hcol)
	h._txt(Vector2(26, vp.y - 82.0), "HEALTH %d" % int(maxf(w.health, 0.0)), 14, hcol)
	if w.armour > 0.0:
		h._txt(Vector2(130, vp.y - 82.0), "VEST %d" % int(w.armour), 14, Color(0.55, 0.78, 1.0))
	# wind: only worth drawing when some of it has been spent
	if w.stamina < 0.995:
		h.draw_rect(Rect2(27, vp.y - 59.0, (hb - 2.0) * w.stamina, 3),
			h.AMBER if w._winded else Color(0.85, 0.92, 1.0, 0.8))
	if w.arena != null and is_instance_valid(w.arena) and w.arena.has_method("hud_state"):
		var cs: Dictionary = w.arena.hud_state()
		h._txt(Vector2(26, vp.y - 104.0), "KILLS %d   DEATHS %d   HEADSHOTS %d   STREAK %d" % [
			int(cs["kills"]), int(cs["deaths"]), int(cs["headshots"]), int(cs["streak"])], 14,
			Color(0.85, 0.92, 1.0))
		h._draw_cqb_map(cs, Rect2(26.0, vp.y - 312.0, 184.0, 184.0))
		# the ladder: what a run of kills buys, and what is waiting to be spent
		var ly: float = vp.y - 300.0
		for k in cs["streaks"]:
			var have: int = int((cs["bank"] as Dictionary).get(k["id"], 0))
			var live: bool = String(k["id"]) == "uav" and float(cs["uav"]) > 0.0
			var txt: String = "%d  %s" % [int(k["key"]), String(k["name"])]
			if have > 0:
				txt += "  READY" + (" x%d" % have if have > 1 else "")
			elif live:
				txt += "  %ds" % int(float(cs["uav"]))
			else:
				txt += "  (%d kills)" % int(k["at"])
			h._txt(Vector2(vp.x - 330.0, ly), txt, 13,
				h.GREEN if have > 0 else (h.AMBER if live else Color(0.5, 0.55, 0.6)),
				HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
			ly += 18.0
	h._txt(Vector2(26, vp.y - 40.0),
		"F2 keys   SPACE vault/climb walls   C crouch   Z prone   F pick up   Q/E lean   G grenade   X flashbang   P view",
		13, Color(0.85, 0.92, 1.0))
	h._draw_log(vp)
	if h.mode != null and is_instance_valid(h.mode):
		h._draw_mode(vp)
