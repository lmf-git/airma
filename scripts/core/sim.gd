extends Node
## Global services: input map bootstrap, the analytic terrain field, mission
## configuration and scoring. Autoloaded as `Sim`.

const WORLD_HALF := 600000.0     # world extends +/- 600 km
const COAST_X := 15000.0         # open water east of here
# ------------------------------------------------------------------ planet
## The world is a cap of a sphere, not a plane.
##
## The centre sits one radius BELOW the origin, so a point on the surface is
## near y = 0 and every position in the world stays inside a hundred kilometres
## or so. That is the whole trick: a real 6371 km radius expressed directly in
## 32-bit floats leaves well under a metre of precision, which is why curved
## worlds normally need a floating origin. Put the centre underneath instead and
## the numbers stay small while the geometry stays honest.
##
## Everything else follows from one function: how far the surface falls below
## the tangent plane at a horizontal distance, which for small angles is exactly
## the sagitta d^2/2R. Subtract it in `height_at` and every one of the two
## hundred odd places that ask where the ground is gets a curved world without
## knowing anything about it.
const PLANET_R := 6_371_000.0
var planet_centre := Vector3(0.0, -PLANET_R, 0.0)

func planet_drop(x: float, z: float) -> float:
	if globe:
		# Exact, because on the planet this is asked at any range. The parabola
		# is the first term of it and holds to thirty metres over the theatre;
		# fifteen thousand kilometres out it is wrong by seven thousand.
		return PLANET_R * (1.0 - cos(sqrt(x * x + z * z) / PLANET_R))
	return (x * x + z * z) / (2.0 * PLANET_R)

## Which way is up here. Away from the centre, which over this world tilts by
## about eight tenths of a degree at the far edge.
## Which way the planet's north pole lies.
##
## Not the same axis the world is a cap on. The theatre sits at the *top* of the
## sphere in world coordinates, but that is a fact about where the cap was put,
## not about the planet's geography: `z` is north-south -- it is what the
## climate bands run along -- so the pole is on the z axis and the airfield is
## on the equator, which is what it has always been climatically.
##
## Negative z, because the flat chart draws increasing z *down* the screen. Get
## this backwards and the globe comes out with the world's north at the bottom.
const PLANET_NORTH := Vector3(0.0, 0.0, -1.0)

# ------------------------------------------------------------------ the chart
#
# Everything in this game asks the world for ground with two numbers, `x` and
# `z`, and there are thousands of those calls. On a flat world they are world
# coordinates. On a planet they cannot be -- a sphere has no flat coordinates --
# but they can be something almost as convenient: *surface offsets from a chart
# origin*, measured along the ground.
#
# That is the hinge the whole spherical world turns on. `height_at(x, z)` keeps
# its signature and its meaning ("the ground this far east and this far south of
# where the chart is centred"), so the aeroplane, the missiles, the vehicles and
# the AI do not have to know the world is round. What changes is only what the
# pair is turned into before the field is asked: a direction from the planet's
# centre, which is what a planetary field is a function of.
#
# The projection is azimuthal equidistant about the origin -- distances along the
# ground from the middle of the chart are exact, which is the property every
# range readout, weapon envelope and turn radius in the game depends on. Away
# from the origin it stretches, like every projection; over the 1200 km the
# theatre covers, that stretch is under a tenth of a per cent.
#
# The origin is fixed at the theatre for now, so `chart_to_dir` reproduces the
# existing world exactly and nothing moves. Making it follow the player is what
# turns the rest of the planet into somewhere you can fly to, and it is the next
# thing this needs.
var chart_origin := Vector3.UP
var chart_east := Vector3.RIGHT
var chart_south := Vector3(0.0, 0.0, 1.0)

## The world is a planet.
##
## It was a flag and a second world for as long as the planet was being built
## next to the flat one; it is the world now. The same `(x, z)` pair is read on
## the chart, the ground under it comes from the planetary field, and what has
## been built on it is carved in wherever it stands.
##
## `--flat` still gets the old 1200 km height field with nothing outside it,
## because a good deal of measurement is written against it and a world you can
## compare against is worth keeping.
var globe := true

## Put the chart somewhere else on the planet. East and south are worked out
## from the planet's own axis, so the chart is always the right way up.
func set_chart(dir: Vector3) -> void:
	chart_origin = dir.normalized()
	var north: Vector3 = -PLANET_NORTH
	# At the poles the axis and the origin are the same line and there is no
	# bearing; any consistent frame will do there.
	var e: Vector3 = chart_origin.cross(north)
	if e.length() < 1e-6:
		e = chart_origin.cross(Vector3.RIGHT)
	chart_east = e.normalized()
	chart_south = chart_east.cross(chart_origin).normalized()
	# The extension does the conversion on its own side, once per call rather
	# than once per sample, so it has to be told where the chart is.
	if native == null and globe:
		push_warning("chart set before the extension exists: the router will "
			+ "survey the flat field while the ground is a planet")
	if native != null:
		native.set_globe(globe)
		native.set_chart(chart_origin, chart_east, chart_south, PLANET_R)

## Chart coordinates to a direction from the planet's centre. `x` is metres east
## along the ground and `z` metres south, which is the sense the flat map has
## always drawn.
func chart_to_dir(x: float, z: float) -> Vector3:
	var s: float = sqrt(x * x + z * z)
	if s < 1e-6:
		return chart_origin
	var ang: float = s / PLANET_R
	var t: Vector3 = (chart_east * (x / s) + chart_south * (z / s)).normalized()
	return (chart_origin * cos(ang) + t * sin(ang)).normalized()

## And back again. Exact inverse of `chart_to_dir` over the near hemisphere.
func dir_to_chart(d: Vector3) -> Vector2:
	var u := d.normalized()
	var c: float = u.dot(chart_origin)
	var t: Vector3 = u - chart_origin * c
	var tl: float = t.length()
	if tl < 1e-12:
		return Vector2.ZERO
	# atan2 of the perpendicular against the parallel, not acos of the parallel.
	# Near the origin `c` is within a float's last digit of 1 and acos throws the
	# answer away: a point one kilometre out came back as the origin itself.
	var ang: float = atan2(tl, c)
	t /= tl
	var s: float = ang * PLANET_R
	return Vector2(t.dot(chart_east) * s, t.dot(chart_south) * s)

## How cold a place is for being where it is, from 0 at the equator to 1 at the
## pole. What the climate bands are cut from.
##
## On the flat world this was `|z|` over most of the map's half width, which is
## the last piece of the authored square in the biome system: it is a function
## of the *chart*, so moving the chart under a fixed piece of ground changes its
## climate, and 1200 km of world was made to span pole to equator.
##
## On the planet it is the real latitude -- so the poles are cold, the equator
## is hot, and a place keeps its climate whoever is looking at it -- multiplied
## by a compression that is written down rather than hidden.
##
## Barely compressed at all, in the end. The tempting number is a large one --
## the whole 1200 km world is 5.4 degrees of a real planet, and 5.4 degrees of
## anywhere is one climate, so squeezing hard gives the ground the variety the
## flat world had. Seven and a half does that and it makes the *planet* absurd:
## snow beyond six degrees of latitude, which is 89 per cent of the surface, and
## a globe that is white from pole to pole with a green fleck on it.
##
## At 1.15 the snow line sits at 44 degrees and the ice covers 30 per cent, which
## is a cold but believable world. The country you fly over is then warm, and its
## variety comes from moisture and from height -- which is where a real place's
## variety comes from over 1200 km, latitude having almost nothing to say across
## five degrees of it.
## Where the climate scale reaches 1, as a fraction of the way to the pole.
##
## The scale is the sine of the latitude times this, so 1 lands at the polar
## circle -- and where the polar circle is, is a fact about the axial tilt: it
## is the latitude beyond which the sun does not set at midsummer, which is
## ninety degrees less the obliquity. This was 1.15, chosen because it looked
## right; it is now the same number the planet's tilt says it should be, so the
## climate bands and the seasons come from one fact instead of two.
##
## Mirrored in `sphere::CLIMATE_SQUEEZE`, which `--suntest` checks.
const CLIMATE_SQUEEZE := 1.0899
## How much warmer midsummer is than midwinter at the pole, on the 0..1 scale
## the biome rule works in. Mirrored in `sphere::SEASON_AMP`.
const SEASON_AMP := 0.12
## Where the planet is in its year: +1 at northern midsummer, -1 at northern
## midwinter. Set from the clock, which is what owns the sun.
var season := 0.0

## What the season is worth in temperature at a place.
##
## Nothing at the equator, most at the poles, and opposite signs either side of
## the line -- which is the whole of the difference between one hemisphere
## having winter and both of them having it at once.
func season_warmth(x: float, z: float) -> float:
	if not globe:
		return 0.0
	return season * chart_to_dir(x, z).dot(PLANET_NORTH) * SEASON_AMP

func climate_lat(x: float, z: float) -> float:
	if not globe:
		return clampf(absf(z) / (WORLD_HALF * 0.85), 0.0, 1.0)
	var d := chart_to_dir(x, z)
	return clampf(absf(d.dot(PLANET_NORTH)) * CLIMATE_SQUEEZE, 0.0, 1.0)

## Carry the built world across when the chart moves.
##
## The floating origin renumbers everything that is *somewhere*, and the roads,
## the towns and the aerodromes are somewhere. They are stored as chart pairs,
## which means that left alone they do not stay where they are when the chart
## moves -- they move with it, and the airfield ends up a hundred and fifty
## kilometres from the airfield. Measured before this existed: 44 of 120 places
## came back with a different biome after a rechart, because the carving under
## them had walked off across the planet.
##
## Only positions are carried. A profile height is an elevation above sea level
## in the flat frame, and that is the same number wherever the chart is.
func rechart_world(o: Vector3, e: Vector3, s2: Vector3) -> void:
	var move := func(p: Vector2) -> Vector2:
		var d: float = sqrt(p.x * p.x + p.y * p.y)
		if d < 1e-6:
			return dir_to_chart(o)
		var ang: float = d / PLANET_R
		var t: Vector3 = (e * (p.x / d) + s2 * (p.y / d)).normalized()
		return dir_to_chart((o * cos(ang) + t * sin(ang)).normalized())
	for f in fields:
		f["at"] = move.call(f["at"] as Vector2)
	roads.rechart(move)
	# The lakes are where they are on the planet; the chart's numbers for them
	# are not.
	index_lakes()

# ------------------------------------------------------- the chart it was built on
## The chart the world's fixed works were laid down in.
##
## The towns, the street furniture, the trees, the road surfaces, the
## aerodromes -- everything built once rather than simulated -- is drawn in the
## coordinates of the chart the world was built on, and none of it was ever
## renumbered when the chart moved. The ground was, the town platforms were,
## the aeroplanes were; the buildings stayed at their old numbers, which in the
## new chart are somewhere else, at a height that belonged to other ground. Fly
## a hundred and fifty kilometres and the towns you left were standing in the
## sea, or a hundred metres underground, or in the air.
##
## They stay in this frame, and `boot_affine` carries them into whichever chart
## is current. It is worked out afresh from this frame every time rather than
## chained from one move to the next, so nothing creeps however many times the
## chart moves, and back on this chart it is exactly the identity.
var boot_origin := Vector3.ZERO
var boot_east := Vector3.ZERO
var boot_south := Vector3.ZERO

## This chart is the one the world is being built on.
func mark_boot_chart() -> void:
	boot_origin = chart_origin
	boot_east = chart_east
	boot_south = chart_south

## Whether the chart has moved off the one the world was built on.
func off_boot_chart() -> bool:
	return boot_origin != Vector3.ZERO and (boot_origin != chart_origin
		or boot_east != chart_east or boot_south != chart_south)

## A point of one chart as a point of another, x and z, in doubles.
##
## The same sums as `chart_to_dir` and `dir_to_chart`, written out in doubles
## because they are differenced: the slope and turn `boot_affine` needs are a
## few hundred metres of difference between numbers a hundred kilometres big,
## and a Vector3 keeps those to a centimetre or so -- which over a 250 m step is
## a turn of four parts in a hundred thousand, and a metre and a half at the
## far edge of a forty kilometre road mesh.
func _chart_carry(fo: Vector3, fe: Vector3, fs: Vector3, to: Vector3, te: Vector3,
		ts: Vector3, x: float, z: float) -> PackedFloat64Array:
	var ux: float = fo.x
	var uy: float = fo.y
	var uz: float = fo.z
	var d: float = sqrt(x * x + z * z)
	if d > 1e-9:
		var tx: float = fe.x * x + fs.x * z
		var ty: float = fe.y * x + fs.y * z
		var tz: float = fe.z * x + fs.z * z
		var tl: float = sqrt(tx * tx + ty * ty + tz * tz)
		var ca: float = cos(d / PLANET_R)
		var sa: float = sin(d / PLANET_R) / tl
		ux = fo.x * ca + tx * sa
		uy = fo.y * ca + ty * sa
		uz = fo.z * ca + tz * sa
	var ul: float = sqrt(ux * ux + uy * uy + uz * uz)
	ux /= ul
	uy /= ul
	uz /= ul
	var c: float = ux * to.x + uy * to.y + uz * to.z
	var px: float = ux - to.x * c
	var py: float = uy - to.y * c
	var pz: float = uz - to.z * c
	var pl: float = sqrt(px * px + py * py + pz * pz)
	if pl < 1e-15:
		return PackedFloat64Array([0.0, 0.0])
	var k: float = atan2(pl, c) * PLANET_R / pl
	return PackedFloat64Array([(px * te.x + py * te.y + pz * te.z) * k,
		(px * ts.x + py * ts.y + pz * ts.z) * k])

## A point laid down on the chart the world was built on, in the chart there is
## now: the same place on the planet, at the same height above the sea.
func boot_to_world(p: Vector3) -> Vector3:
	if not off_boot_chart():
		return p
	var q := _chart_carry(boot_origin, boot_east, boot_south, chart_origin,
		chart_east, chart_south, p.x, p.z)
	return Vector3(q[0], p.y - sea_shell(p.x, p.z) + sea_shell(q[0], q[1]), q[1])

## And back: a point in the chart there is now, in the one the world was built on.
func world_to_boot(p: Vector3) -> Vector3:
	if not off_boot_chart():
		return p
	var q := _chart_carry(chart_origin, chart_east, chart_south, boot_origin,
		boot_east, boot_south, p.x, p.z)
	return Vector3(q[0], p.y - sea_shell(p.x, p.z) + sea_shell(q[0], q[1]), q[1])

func _boot_map(x: float, y: float, z: float) -> PackedFloat64Array:
	var q := _chart_carry(boot_origin, boot_east, boot_south, chart_origin,
		chart_east, chart_south, x, z)
	return PackedFloat64Array([q[0], y - sea_shell(x, z) + sea_shell(q[0], q[1]), q[1]])

## The move from the chart the world was built on to the one there is now, as
## one transform good around `c` (a point in the built-on chart).
##
## Not a rotation and a shift. The two charts are each the planet laid flat
## about a different point, and between them the same ground stands at a
## height that changes across it -- the curve falls away from one middle and
## not the other -- so the carry is a turn, a shift and a lean: x and z turned
## and moved, y raised by an amount that runs linearly across the ground. The
## curvature itself is the same in both charts and drops out, so the lean is
## right to a few centimetres over tens of kilometres; what is left is the
## projection's own stretch, which is under a metre forty kilometres from `c`
## with the charts a hundred and fifty apart. Uprights stay upright: the y
## axis is left alone, and what leans is the ground and everything lying on it.
func boot_affine(c: Vector3) -> Transform3D:
	if not off_boot_chart():
		return Transform3D.IDENTITY
	const H := 250.0
	var m0 := _boot_map(c.x, c.y, c.z)
	var mxp := _boot_map(c.x + H, c.y, c.z)
	var mxn := _boot_map(c.x - H, c.y, c.z)
	var mzp := _boot_map(c.x, c.y, c.z + H)
	var mzn := _boot_map(c.x, c.y, c.z - H)
	var ax: float = (mxp[0] - mxn[0]) / (2.0 * H)
	var ay: float = (mxp[1] - mxn[1]) / (2.0 * H)
	var az: float = (mxp[2] - mxn[2]) / (2.0 * H)
	var bx: float = (mzp[0] - mzn[0]) / (2.0 * H)
	var by: float = (mzp[1] - mzn[1]) / (2.0 * H)
	var bz: float = (mzp[2] - mzn[2]) / (2.0 * H)
	# The shift, worked in doubles: it is the difference of two numbers the
	# size of the chart move.
	var ox: float = m0[0] - (ax * c.x + bx * c.z)
	var oy: float = m0[1] - (ay * c.x + c.y + by * c.z)
	var oz: float = m0[2] - (az * c.x + bz * c.z)
	return Transform3D(Basis(Vector3(ax, ay, az), Vector3.UP, Vector3(bx, by, bz)),
		Vector3(ox, oy, oz))

## Latitude of a point on the ground, in radians: zero at the airfield, positive
## toward the top of the chart. Real, in the sense that it is the angle at the
## planet's centre -- the whole 1200 km world is inside five and a half degrees
## of the equator, which is what a 1200 km world on a 6371 km planet is.
func latitude_at(x: float, z: float) -> float:
	var u := Vector3(x, sqrt(maxf(PLANET_R * PLANET_R - x * x - z * z, 0.0)), z)
	return asin(clampf(u.normalized().dot(PLANET_NORTH), -1.0, 1.0))

func up_at(p: Vector3) -> Vector3:
	return (p - planet_centre).normalized()

## Height above the sphere, not above the y = 0 plane. Sixty kilometres out
## those differ by 283 m.
func altitude(p: Vector3) -> float:
	return p.distance_to(planet_centre) - PLANET_R

## Gravity, as Newton has it: towards the planet's centre and falling off with
## the square of the distance from it.
##
## This was a flat 9.81 whatever the height, which is right on a runway and
## wrong everywhere a rocket goes: at four hundred kilometres the real figure
## is 8.7, and it is that inverse square -- not the number at the ground --
## that makes an orbit close on itself. `GM` is the planet's gravitational
## parameter, chosen so the surface value is still exactly 9.81.
const GM := 9.81 * PLANET_R * PLANET_R
func gravity_at(p: Vector3) -> Vector3:
	var r: Vector3 = p - planet_centre
	var d2: float = maxf(r.length_squared(), PLANET_R * PLANET_R * 0.25)
	return r * (-GM / (d2 * sqrt(d2)))

## Speed of a circular orbit at a height, and how long one lap takes.
func orbit_speed(alt: float) -> float:
	return sqrt(GM / (PLANET_R + maxf(alt, 0.0)))

func orbit_period(alt: float) -> float:
	var a: float = PLANET_R + maxf(alt, 0.0)
	return TAU * sqrt(a * a * a / GM)

# ------------------------------------------------------------------ the moon
## One moon, at the real one's size, distance and month.
const MOON_R := 1_737_400.0
const MOON_GM := 4.9028e12
const MOON_DIST := 384_400_000.0
const MOON_PERIOD := 27.32 * 86400.0
## The plane it goes round in, as the axis of it, in the planet's own frame:
## tipped off the planet's axis so it is not always over the equator.
const MOON_AXIS := Vector3(0.1908, 0.9063, 0.3772)
## The clock everything in space runs on. It is the world's own time until a
## spacecraft is coasting on time warp, when it runs ahead with the ship.
var space_time := 0.0

## Where the moon is, as a direction from the planet's centre in the planet's
## frame -- the frame `chart_origin` and `PLANET_NORTH` are written in.
func moon_dir() -> Vector3:
	var ax: Vector3 = MOON_AXIS.normalized()
	var u: Vector3 = ax.cross(Vector3.RIGHT).normalized()
	var w: Vector3 = ax.cross(u)
	var a: float = 0.9 + space_time * TAU / MOON_PERIOD
	return (u * cos(a) + w * sin(a)).normalized()

## Between the planet's own frame -- metres from its centre, along the axes
## `chart_origin` and `PLANET_NORTH` are written in -- and the world.
##
## There are two ways to do it and they are for different things. The world is
## not quite Euclidean: `x` and `z` are distance *along the ground* from the
## middle of the chart, and `y` is height with the planet's curve taken off.
## Anything that has to agree with the ground -- stand on it, hit it, be found
## by what is on it -- goes through `space_to_world`, which is the same rule
## `rechart` renumbers the world by and holds at any range. The moon, which
## only has to be in the right part of the sky, takes the straight rotation.
func space_to_world(p: Vector3) -> Vector3:
	var r: float = maxf(p.length(), 1.0)
	var q: Vector2 = dir_to_chart(p / r)
	return Vector3(q.x, (r - PLANET_R) - planet_drop(q.x, q.y), q.y)

func world_to_space(p: Vector3) -> Vector3:
	return chart_to_dir(p.x, p.z) * (PLANET_R + p.y + planet_drop(p.x, p.z))

func planet_to_world(p: Vector3) -> Vector3:
	return Vector3(p.dot(chart_east), p.dot(chart_origin) - PLANET_R, p.dot(chart_south))

## A direction or a velocity: the rotation, without the drop.
func planet_to_world_dir(d: Vector3) -> Vector3:
	return Vector3(d.dot(chart_east), d.dot(chart_origin), d.dot(chart_south))

func world_to_planet_dir(d: Vector3) -> Vector3:
	return chart_east * d.x + chart_origin * d.y + chart_south * d.z

## The moon as a world point. A long way off: good for a direction and for the
## pull of it, not for standing something on.
func moon_world() -> Vector3:
	return planet_to_world(moon_dir() * MOON_DIST)

## Time warp, for what is coasting above the air. A lap of the planet is an
## hour and a half and an intercontinental shot is half of one; neither is
## something to sit through. It only ever applies to a thing in free fall
## outside the atmosphere -- nothing under power and nothing in the air is
## hurried -- and the rest of the world goes on at its own pace underneath.
const WARPS := [1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 1000.0, 10000.0]
var space_warp := 1.0
## What the space clock is actually running at this tick: the warp, when the
## player's own ship is the thing coasting, and 1 otherwise.
var space_rate := 1.0

func warp_step(by: int) -> void:
	var i: int = WARPS.find(space_warp)
	i = clampi((0 if i < 0 else i) + by, 0, WARPS.size() - 1)
	space_warp = WARPS[i]

## How fast a body at this height may be hurried.
func warp_at(alt: float, powered: bool) -> float:
	if powered or alt < 100000.0:
		return 1.0
	# close in, a tick of the fastest warp is a sixth of the way round
	return minf(space_warp, 100.0) if alt < 400000.0 else space_warp

## How much smaller than life the planet is being drawn, and where the moon is
## from the eye, for a spacecraft a long way out: see `LaunchVehicle._place`.
var view_scale := 1.0
var view_moon := Vector3.INF

## The water's surface at a point: the sea's, or a lake's where there is one.
## The ocean is a shell, so it falls away with everything else — a flat sea
## plane against curved ground would flood the far half of the map. This is the
## MEAN surface: the swell rides on top of it.
##
## A lake's surface counts. Nearly everything that asks this is asking where the
## water is -- what a round splashes into, what a man wades in, where a town may
## not be built, what a tree may not grow under -- and there was only ever one
## kind of water to ask about. What wants the curve of the planet and nothing
## else, the chart's own arithmetic, asks `sea_shell`.
func sea_at(x: float, z: float) -> float:
	var shell: float = WATER_LEVEL - planet_drop(x, z)
	var lv: float = lake_level_at(x, z)
	return shell + lv if lv > 0.0 else shell

## The sea's own level with no lake in it: the curve of the planet.
func sea_shell(x: float, z: float) -> float:
	return WATER_LEVEL - planet_drop(x, z)

# -------------------------------------------------------------------- lakes
## The lakes and inland seas round the chart, as the extension found them: x and
## z of the middle, the rim's radius and the surface above sea level, four
## floats each. Rebuilt whenever the chart moves.
var lakes := PackedFloat32Array()
var _lake_grid: Dictionary = {}
const LAKE_CELL := 20000.0
## Far enough that the ground anyone can see from inside the air is covered.
const LAKE_REACH := 900000.0
signal lakes_changed

func index_lakes() -> void:
	lakes = PackedFloat32Array()
	_lake_grid = {}
	if globe and native != null and native.has_method("lakes_in"):
		lakes = native.lakes_in(0.0, 0.0, LAKE_REACH)
	for li in lakes.size() >> 2:
		var b: int = li * 4
		var cx: float = lakes[b]
		var cz: float = lakes[b + 1]
		var r: float = lakes[b + 2]
		for cj in range(int(floor((cz - r) / LAKE_CELL)), int(floor((cz + r) / LAKE_CELL)) + 1):
			for ci in range(int(floor((cx - r) / LAKE_CELL)), int(floor((cx + r) / LAKE_CELL)) + 1):
				var k := Vector2i(ci, cj)
				var arr: PackedInt32Array = _lake_grid.get(k, PackedInt32Array())
				arr.append(li)
				_lake_grid[k] = arr
	lakes_changed.emit()

## A lake's surface over this point, in metres above sea level, or -INF where
## there is no lake: over the whole of its rim, wet or not, the way the sea's
## surface is everywhere whether the ground is under it or not.
func lake_level_at(x: float, z: float) -> float:
	if _lake_grid.is_empty():
		return -INF
	var cell: Variant = _lake_grid.get(Vector2i(int(floor(x / LAKE_CELL)), int(floor(z / LAKE_CELL))))
	if cell == null:
		return -INF
	var lv := -INF
	for li in (cell as PackedInt32Array):
		var b: int = li * 4
		var dx: float = x - lakes[b]
		var dz: float = z - lakes[b + 1]
		var r: float = lakes[b + 2]
		if dx * dx + dz * dz < r * r:
			lv = maxf(lv, lakes[b + 3])
	return lv

# -------------------------------------------------------------------- swell
## Two long crossing swells, five hundred metres from crest to crest and a
## couple of metres high. Defined here and nowhere else: the water shader is
## handed the same constants and the same clock, so what a hull rides is exactly
## what you can see it riding. A sea drawn by one formula and floated on by
## another is worse than a flat one.
## Three components, because a real sea is a spectrum and one wavelength is
## not. Two long swells crossing at 450 and 400 m carry the heave; a 70 m chop
## on top of them is what a small hull actually pitches to. Without the short
## one every ship behaved the same — a 500 m swell is so long that a 47 m boat
## and a 257 m assault ship both simply follow it, and the size of the hull
## stopped meaning anything.
##
## The frequencies are not free: in deep water omega = sqrt(g*k), so a long wave
## is slow and a short one quick. Setting them by eye gives a sea where the big
## swell hurries and the chop crawls, which reads as wrong even if you cannot
## say why.
const SWELL_A := 1.25            # metres, the long swell    (454 m, 17.1 s)
const SWELL_B := 0.75            # crossing it               (401 m, 16.0 s)
const SWELL_C := 0.42            # the chop on top           ( 70 m,  6.7 s)
const SWELL_KA := Vector2(0.01210, 0.00670)
const SWELL_KB := Vector2(-0.00740, 0.01380)
const SWELL_KC := Vector2(0.06200, 0.06500)
const SWELL_WA := 0.368
const SWELL_WB := 0.392
const SWELL_WC := 0.939
## Advanced by the world, not read from the engine's clock, so the shader and
## the physics cannot drift apart across a pause or a frame spike.
var sea_time := 0.0

func wave_at(x: float, z: float) -> float:
	return SWELL_A * sin(SWELL_KA.x * x + SWELL_KA.y * z + sea_time * SWELL_WA) \
		+ SWELL_B * sin(SWELL_KB.x * x + SWELL_KB.y * z + sea_time * SWELL_WB) \
		+ SWELL_C * sin(SWELL_KC.x * x + SWELL_KC.y * z + sea_time * SWELL_WC)

## The swell as it is drawn, from wherever the camera is.
##
## The sea is a disc of vertices about the eye that grows coarser with
## distance, and each wave is let go where the mesh is too coarse to carry it:
## the seventy metre chop is gone a few hundred metres out, the long swells by
## two or three kilometres. A hull riding `wave_at` rides all of it regardless,
## so seen from any distance a ship rolled and pitched and bobbed on water drawn
## calm -- not floating on the sea, but moving about on top of it. Hulls take
## the same fade the drawn sea does at their distance from the eye, with the
## mesh's own numbers (see the sea in `Terrain`).
const SEA_SPOKE_ANG := TAU / 192.0
const SEA_INNER_STEP := 3.0

func wave_seen(x: float, z: float) -> float:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var d := 0.0
	if cam != null:
		d = Vector2(x - cam.global_position.x, z - cam.global_position.z).length()
	var sp: float = maxf(SEA_INNER_STEP, d * SEA_SPOKE_ANG)
	return _kept(sp, SWELL_KA) * SWELL_A * sin(SWELL_KA.x * x + SWELL_KA.y * z + sea_time * SWELL_WA) \
		+ _kept(sp, SWELL_KB) * SWELL_B * sin(SWELL_KB.x * x + SWELL_KB.y * z + sea_time * SWELL_WB) \
		+ _kept(sp, SWELL_KC) * SWELL_C * sin(SWELL_KC.x * x + SWELL_KC.y * z + sea_time * SWELL_WC)

## Is the sea drawn flat here? Far enough from the eye its vertices are too far
## apart to carry even the longest swell, `wave_seen` is nought whatever the
## clock says, and a hull out there need not ask five times a tick to be told.
func swell_gone(x: float, z: float) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	var d: float = Vector2(x - cam.global_position.x, z - cam.global_position.z).length()
	var longest: float = TAU / minf(SWELL_KA.length(), minf(SWELL_KB.length(), SWELL_KC.length()))
	return d * SEA_SPOKE_ANG >= 0.25 * longest and SEA_INNER_STEP < 0.25 * longest

## How much of a wave the drawn sea keeps where its vertices are `sp` apart:
## the shader's `keep`, all of it at eight points a wave, none at four.
static func _kept(sp: float, k: Vector2) -> float:
	var lam: float = TAU / k.length()
	return 1.0 - smoothstep(0.125 * lam, 0.25 * lam, sp)

## The surface a hull actually floats on: the shell plus the swell riding on it.
func sea_surface(x: float, z: float) -> float:
	# A lake has no ocean swell on it.
	if lake_level_at(x, z) > 0.0:
		return sea_at(x, z)
	return sea_at(x, z) + wave_at(x, z)

const WATER_LEVEL := -35.0
const RUNWAY_LEN := 3000.0       # 36/18, aligned with the Z axis
const RUNWAY_HALF_W := 23.0
const RUNWAY_ELEV := 0.0


signal mission_event(text: String, kind: int)   # kind: 0 info, 1 good, 2 bad
## One line of the kill feed: see `KillFeed`.
signal kill_event(e: Dictionary)

enum Ev { INFO, GOOD, BAD }

## Continents, for deciding which side of the map a place belongs to. The
## height field itself -- the continents, the rivers, the ridges, the detail --
## lives in `field.rs` and is the extension's business; this is the one noise
## the game still reads directly.
var noise_cont := FastNoiseLite.new()
## Whose ground it is. Deliberately not the continental field: that one carries
## three fractal octaves because coastlines want the detail, and an *angle*
## taken from a field with detail in it flips every few kilometres. Nations came
## out as a 16 km checkerboard rather than as territories.
var noise_faction := FastNoiseLite.new()
## And whose ground it is on the planet.
##
## A separate field because it has to be sampled on the *direction*, not on the
## chart pair. Territory belongs to the planet: read off the pair it would move
## under your feet every time the chart did, and the country you were standing
## in would change because you flew a hundred and fifty kilometres.
var noise_faction3 := FastNoiseLite.new()
## Temperature and moisture on the planet, matching `sphere::climate` in the
## extension exactly: same seeds, same octaves, same frequencies on the unit
## sphere. Two copies of one rule, and they have to stay one rule.
var noise_temp3 := FastNoiseLite.new()
var noise_moist3 := FastNoiseLite.new()
## The native extension. It owns the height field: see `height_at`.
var native: Object = null

var noise_temp := FastNoiseLite.new()
var noise_moist := FastNoiseLite.new()

var selected_jet := &"f22"
var mission := &"takeoff"
var weather := "scattered"
var debug_weapons := false        # set by --debugweapons, prints impact data
var net: Node = null              # the live NetLink, or null offline
var roads := RoadNet.new()
var biomes := Biomes.new()
var keys := KeyBindings.new()
## True while a full screen page owns the mouse -- the map, the action menu,
## the pause menu. Weapons are polled straight from the input actions rather
## than through the GUI, so without this a click on the map also pulled the
## trigger.
var ui_modal := false
## The pause page is up in a session. Nothing stops -- a match other people are
## playing cannot be frozen by one of them -- so the controls are let go of
## instead: the man stands, the vehicle coasts, nothing fires.
var menu_open := false
## Looking through the satellite view (`SatView`): the controls are let go of,
## as with the pause page.
var spectating := false
## A range with no air threat on it. Set by the STRIKE mission: the vehicles,
## shipping and helicopters on it are there to be attacked from the air, and
## none of them shoots at an aeroplane -- not the batteries, not a tank's main
## gun at a low pass, not a ship's tubes, not a gunship's missiles.
var no_air_threat := false
## True while the chat line is open. Held keys keep reporting through
## `Input.is_action_pressed` no matter what consumes the event, so typing "d"
## in the chat rolled the aeroplane right. Every control surface reads through
## the three helpers below instead, and they go quiet while a line is open.
var typing := false
## Where the last explosion was drawn, for the harness.
var salvo_watch := false
var salvo_weapon := "gbu32"
var salvo_mark := Vector3.INF
var salvo_log: Array = []
var last_burst := Vector3.INF
var last_burst_r := 0.0
## Sensor suite state, shared by the HUD, the pod and the map.
const RADAR_RANGES := [10000.0, 20000.0, 40000.0, 80000.0]
var radar_range_idx := 2
var panel_left := 0               # 0 off, 1 sensor, 2 radar, 3 minimap
var panel_right := 2

func radar_range() -> float:
	return RADAR_RANGES[clampi(radar_range_idx, 0, RADAR_RANGES.size() - 1)]

# ---------------------------------------------------------------- settings
## What survives being closed. Nothing did: there was no options page, no
## ConfigFile, no rebinding, so weather, fly-by-wire, radar range and the mouse
## stick were all back to their defaults every single run.
const SETTINGS_PATH := "user://settings.cfg"

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("sim", "weather", weather)
	cf.set_value("sim", "assist", assist)
	cf.set_value("sim", "radar_range_idx", radar_range_idx)
	cf.set_value("sim", "mouse_gain", mouse_gain)
	cf.set_value("sim", "invert_pitch", invert_pitch)
	for b in volumes:
		cf.set_value("audio", String(b), float(volumes[b]))
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "vsync", vsync)
	var err := cf.save(SETTINGS_PATH)
	if err != OK:
		push_warning("could not save settings: %d" % err)

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	weather = String(cf.get_value("sim", "weather", weather))
	assist = bool(cf.get_value("sim", "assist", assist))
	radar_range_idx = int(cf.get_value("sim", "radar_range_idx", radar_range_idx))
	mouse_gain = float(cf.get_value("sim", "mouse_gain", mouse_gain))
	invert_pitch = bool(cf.get_value("sim", "invert_pitch", invert_pitch))
	for b in volumes:
		volumes[b] = clampf(float(cf.get_value("audio", String(b), volumes[b])), 0.0, 1.0)
	fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cf.get_value("display", "vsync", vsync))

## Pointer scaling and pitch sense, which every simulator has and this had
## hard-coded. Both were saved and loaded and then read by nothing at all:
## every mouse handler goes through `mouse_rel` now.
var mouse_gain := 1.0
var invert_pitch := false

## A mouse movement as the player has asked for it: scaled, and with the
## vertical turned over if they fly or look that way.
func mouse_rel(e: InputEventMouseMotion) -> Vector2:
	var r: Vector2 = e.relative * mouse_gain
	if invert_pitch:
		r.y = -r.y
	return r

# ------------------------------------------------------------------- audio
## Every sound went straight to Master, so the only volume there was the
## operating system's. Three groups under it, each with its own slider: what
## the weapons and the world sound like, the noise of whatever you are in, and
## the tones and ticks that are there to tell you something.
const BUSES := [&"Master", &"Effects", &"Engines", &"Interface"]
var volumes := {&"Master": 1.0, &"Effects": 1.0, &"Engines": 1.0, &"Interface": 1.0}

func _make_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, &"Master")
	apply_audio()

func apply_audio() -> void:
	for b in volumes:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		var v: float = float(volumes[b])
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))

# ----------------------------------------------------------------- display
var fullscreen := false
var vsync := true

## Not at start-up for a harness run: a test that asks for a window of a given
## size, or none at all, gets that rather than whatever was last chosen on the
## page. `now` is the page itself, where someone has just asked for it.
func apply_display(now := false) -> void:
	if DisplayServer.get_name() == "headless" \
			or (not now and not OS.get_cmdline_user_args().is_empty()):
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync
		else DisplayServer.VSYNC_DISABLED)
	var fs: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fs != fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)

# --------------------------------------------------------------------- IFF
## Who a contact is, as far as the observer can actually tell.
##
## Everything filtered on `team` directly, which meant identification was
## perfect and free: there was nothing that could be uncertain, nothing that
## could be got wrong. A radar return is a return — what makes it a friend is
## a transponder answering, and that only carries so far.
enum Iff { FRIEND, HOSTILE, UNKNOWN }

## How far a transponder interrogation is good for. Beyond this the return is
## still painted, it just has no name against it.
const IFF_RANGE := 46_000.0

func iff(observer: Node, contact: Node) -> int:
	if not is_instance_valid(observer) or not is_instance_valid(contact):
		return Iff.UNKNOWN
	if not ("team" in observer) or not ("team" in contact):
		return Iff.UNKNOWN
	# Your own side answers wherever it is: you are on the same net.
	if int(observer.team) == int(contact.team):
		return Iff.FRIEND
	if not (observer is Node3D) or not (contact is Node3D):
		return Iff.HOSTILE
	var d: float = (observer as Node3D).global_position.distance_to(
		(contact as Node3D).global_position)
	# Something that does not answer, close enough to have been asked properly,
	# is hostile. Further out it is simply a contact.
	return Iff.HOSTILE if d <= IFF_RANGE else Iff.UNKNOWN

func iff_label(code: int) -> String:
	match code:
		Iff.FRIEND:
			return "FRIENDLY"
		Iff.HOSTILE:
			return "HOSTILE"
		_:
			return "UNKNOWN"

## Which satellite the ASAT launchers have been assigned, picked on the map.
## Kept here rather than on the map page because the launcher has to read it and
## the map is not always up.
var sat_target: Node = null

## Ask a friendly reconnaissance satellite what it can see. This is what the
## terminal link on the TAB menu does: a satellite that only ever widened a
## number was not something you could *use*.
func satellite_survey(team: int) -> Dictionary:
	var out := {"sat": "", "seen": 0, "centre": Vector3.INF}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	var eye: Node3D = null
	for sat in tree.get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		if ("team" in sat) and int(sat.team) != team:
			continue
		if String(sat.get("kind")) != "recon":
			continue
		eye = sat as Node3D
		break
	if eye == null:
		return out
	out["sat"] = String(eye.call("display_name")) if eye.has_method("display_name") \
		else "satellite"
	# Everything hostile under it, and where the weight of it is. A survey is a
	# picture of where they are, not a list.
	var sum := Vector3.ZERO
	var n := 0
	for x in tree.get_nodes_in_group("hittable"):
		if not is_instance_valid(x) or not (x is Node3D):
			continue
		if not ("team" in x) or int(x.team) == team:
			continue
		if x.has_method("is_alive") and not x.is_alive():
			continue
		var q: Vector3 = (x as Node3D).global_position
		if Vector2(q.x - eye.global_position.x, q.z - eye.global_position.z).length() \
				> SAT_REACH:
			continue
		sum += q
		n += 1
	out["seen"] = n
	if n > 0:
		out["centre"] = sum / float(n)
	return out

## How many of something are already in the world. The admin page uses it so
## that asking for a thing twice tops the set up rather than laying down a
## duplicate of everything.
func census(group: String) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var n := 0
	for x in tree.get_nodes_in_group(group):
		if is_instance_valid(x):
			n += 1
	return n

# ------------------------------------------------------- what can be hit
## Everything a round, a fragment or a look-out might care about, gathered once
## a physics tick and shared.
##
## Every shell in the air walked the whole "hittable" group on every tick, and
## asked each thing in it whether it had an `is_alive`, whether it was, where it
## was, whether it had a `hit_radius` and what that was -- six calls into the
## engine per contact per round, 120 times a second. Thirty rounds of artillery
## in flight over a battle was three quarters of a millisecond a frame, the
## second largest script cost in the game, to learn that a shell four
## kilometres up had not hit a tank. Asked once and kept as plain arrays, the
## question each round asks of each contact is one subtraction and a compare,
## and only what is actually near it is looked at properly.
##
## A tick stale at worst: whatever dies inside one still answers `is_alive`
## for whoever gets as far as asking, and whatever is made inside one is a tick
## late -- eight milliseconds.
var hit_nodes: Array = []
var hit_pos := PackedVector3Array()
var hit_rad := PackedFloat32Array()
## The side each belongs to, or -1 for something with none.
var hit_team := PackedInt32Array()
## Men on foot, who are kept off the radar picture and so are not "hittable".
var man_nodes: Array = []
var man_pos := PackedVector3Array()
var man_team := PackedInt32Array()
var _hit_tick := -1

func hit_scan() -> void:
	var tick := Engine.get_physics_frames()
	if tick == _hit_tick:
		return
	_hit_tick = tick
	var tree := Engine.get_main_loop() as SceneTree
	hit_nodes.clear()
	man_nodes.clear()
	if tree == null:
		hit_pos.resize(0)
		hit_rad.resize(0)
		hit_team.resize(0)
		man_pos.resize(0)
		man_team.resize(0)
		return
	var all: Array = tree.get_nodes_in_group("hittable")
	hit_pos.resize(all.size())
	hit_rad.resize(all.size())
	hit_team.resize(all.size())
	var k := 0
	for n in all:
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		hit_nodes.append(n)
		hit_pos[k] = (n as Node3D).global_position
		hit_rad[k] = float(n.hit_radius()) if n.has_method("hit_radius") else 6.0
		hit_team[k] = int(n.team) if "team" in n else (int(n.side) if "side" in n else -1)
		k += 1
	hit_pos.resize(k)
	hit_rad.resize(k)
	hit_team.resize(k)
	var men: Array = tree.get_nodes_in_group("infantry")
	man_pos.resize(men.size())
	man_team.resize(men.size())
	k = 0
	for n in men:
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		man_nodes.append(n)
		man_pos[k] = (n as Node3D).global_position
		# a man on foot carries his side as `side`; a soldier as `team`
		man_team[k] = int(n.team) if "team" in n else (int(n.side) if "side" in n else -1)
		k += 1
	man_pos.resize(k)
	man_team.resize(k)

# --------------------------------------------------------------- objective
## Somewhere the player has decided matters. Set with shift and click on the
## tactical map, and deliberately kept here rather than on the map page: the
## whole point of it is that you can see it from the cockpit, from the chase
## camera, from a tank and from a ship's bridge, which means everything that
## draws has to be able to ask for it.
var objective := Vector3.INF

func set_objective(at: Vector3) -> void:
	objective = at
	report("objective marked at %d, %d" % [int(at.x), int(at.z)], Ev.INFO)

func clear_objective() -> void:
	objective = Vector3.INF
	report("objective cleared", Ev.INFO)

# ---------------------------------------------------------------- coverage
## How far a side can actually see, which is not the same as how far its own
## radar reaches. An aeroplane's set is limited by what it can carry; what
## extends it is somebody else's — an early warning aircraft orbiting behind the
## line, or a reconnaissance satellite passing over.
##
## Both existed as objects with nothing attached to them: the E-3 was a large
## aeroplane that did nothing and a satellite was something to shoot at for no
## gain. This is what they are for, and it is why killing one matters.
const AWACS_REACH := 190_000.0
const SAT_REACH := 130_000.0

## Not cached. The first cut of this held the answer for a frame, keyed on
## `Engine.get_frames_drawn()` — which does not advance in a headless run, so
## the very first answer was returned for the rest of the session and an E-3
## taking off changed nothing. It is two small groups and it is asked once per
## page draw, not once per contact, so there is nothing here worth caching.
func coverage(team: int) -> float:
	var reach: float = radar_range()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		# An early warning aircraft has to be up and alive to be any use.
		for n in tree.get_nodes_in_group("awacs"):
			if not is_instance_valid(n) or not (n is Node3D):
				continue
			if ("team" in n) and int(n.team) != team:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			reach = maxf(reach, AWACS_REACH)
		for sat in tree.get_nodes_in_group("satellites"):
			if not is_instance_valid(sat):
				continue
			if ("team" in sat) and int(sat.team) != team:
				continue
			if String(sat.get("kind")) != "recon":
				continue
			reach = maxf(reach, SAT_REACH)
		# Ground based air defence. A battery is a radar with rounds attached
		# and it was contributing nothing to the picture — the side it belongs
		# to could not see any further for having one, which is most of what a
		# battery is actually for.
		for v in tree.get_nodes_in_group("air_radar"):
			if not is_instance_valid(v):
				continue
			if ("team" in v) and int(v.team) != team:
				continue
			if v.has_method("is_alive") and not v.is_alive():
				continue
			if v.has_method("radar_range"):
				reach = maxf(reach, float(v.call("radar_range")))
	return reach

## Is this side's picture being helped by something other than its own radar?
## The HUD says so, because a picture that quietly doubles and then quietly
## halves again when a satellite is shot down is a mystery rather than a system.
func coverage_source(team: int) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	var got := ""
	for v in tree.get_nodes_in_group("air_radar"):
		if is_instance_valid(v) and (not ("team" in v) or int(v.team) == team) \
				and (not v.has_method("is_alive") or v.is_alive()):
			got = "GCI"
	for sat in tree.get_nodes_in_group("satellites"):
		if is_instance_valid(sat) and (not ("team" in sat) or int(sat.team) == team) \
				and String(sat.get("kind")) == "recon":
			got = "SAT"
	# An early warning aircraft reaches further than the satellite does, so if
	# both are up it is the one carrying the picture.
	for n in tree.get_nodes_in_group("awacs"):
		if is_instance_valid(n) and (not ("team" in n) or int(n.team) == team) \
				and (not n.has_method("is_alive") or n.is_alive()):
			got = "AWACS"
	return got
var assist := true
var last_landing := {}
var score := 0
var discord_presence = null
## What the presence says you are doing, kept up to date by the world: the
## mode actually being played and the seat actually being sat in. It read the
## hangar's last choice -- `mission` and `selected_jet` -- so a street fight on
## foot was "Runway Operations, flying an F-22".
var presence_mode := ""
var presence_seat := ""

# --------------------------------------------------------------------------
func _ready() -> void:
	# Whatever the player chose last time, before anything reads a default.
	load_settings()
	_make_buses()
	apply_display()
	# Before the noise fields, so nothing can sample the GDScript ones first and
	# then be answered by the native field later in the same run.
	if ClassDB.class_exists("Terra"):
		native = ClassDB.instantiate("Terra")
	else:
		# There is no GDScript path any more. The height field, the road
		# router, the corridor and the survey all live in the extension, and
		# keeping a second implementation of each in here meant two answers to
		# the same question that could drift apart -- which, for a field the
		# towns, roads and colliders are all sited against, tears the world in
		# half. Better to fail here, loudly, than to run half a world.
		push_error("flight_native is missing. Build it with: "
			+ "cd native && GODOT4_BIN=<godot> cargo build --release")
	if native != null:
		var lim: PackedFloat32Array = native.survey_limits()
		roads.road_grade_max = lim[1]
		roads.road_grade_hairpin = lim[2]
		roads.road_cut_hard = lim[5]
		roads.road_fill_hard = lim[6]
	if ClassDB.class_exists("DiscordPresence"):
		discord_presence = ClassDB.instantiate("DiscordPresence")
	_setup_noise()
	keys.install()

func _setup_noise() -> void:
	# The home field, before anything can ask for a height. Registering it from
	# the world's _ready was too late: the terrain had already been built by
	# then, with no fields in the list at all, so nothing flattened the airfield
	# and the runway ended up buried under the ground it was supposed to be on.
	fields.clear()
	register_field(Vector2.ZERO, 0.0, RUNWAY_ELEV)

	noise_cont.seed = 20260827
	noise_cont.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# a shade over two hundred kilometres to a lobe, so a continent is a day's
	# flying across and the seas between them are real seas
	noise_cont.frequency = 0.0000047
	noise_cont.fractal_octaves = 3
	noise_cont.fractal_lacunarity = 2.3
	noise_cont.fractal_gain = 0.45
	noise_faction.seed = 20260903
	noise_faction.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# One octave, and slow: a feature is most of the width of the world, so a
	# nation holds a piece of ground you can fly across rather than a patch.
	# Measured by walking lines across the world and counting how far one flag
	# lasts, this takes the mean run from 22 km to 95 km and the median from
	# 16 km to 80 km, with the six shares still even -- 13 to 20 per cent each.
	noise_faction.frequency = 0.0000024
	noise_faction.fractal_octaves = 1
	noise_faction3.seed = 20260903
	noise_faction3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# On the unit sphere, so a frequency is a number of features round the
	# planet rather than a size in metres. Measured rather than derived: 19.5
	# puts a border about every 89 km of surface, against the 95 km the flat
	# world was tuned to. The first estimate of 68 was out by three and a half
	# times and gave 27 km -- a checkerboard again, on a planet this time.
	noise_faction3.frequency = 19.5
	noise_faction3.fractal_octaves = 1
	noise_temp3.seed = 515
	noise_temp3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_temp3.frequency = 40.0
	noise_temp3.fractal_octaves = 2
	noise_moist3.seed = 811
	noise_moist3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_moist3.frequency = 29.0
	noise_moist3.fractal_octaves = 3

	noise_temp.seed = 515
	noise_temp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# Thirty-six kilometres to a lobe gave mottling, not regions: across a
	# twelve hundred kilometre world every biome was a patch a few minutes wide
	# and there was no such thing as "the desert" or "the northern forest".
	noise_temp.frequency = 0.0000062
	noise_temp.fractal_octaves = 2

	noise_moist.seed = 811
	noise_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_moist.frequency = 0.0000085
	noise_moist.fractal_octaves = 3


## How "airfield flat" a spot is: 1 = perfectly level apron, 0 = open terrain.
## Airfields. There was exactly one, at the origin, hard-wired into the height
## field and into every question about what you are rolling on — so the other
## side had nowhere to operate from and every aeroplane in the world staged off
## the same strip.
var fields: Array = []           # {"at": Vector2, "yaw": float, "elev": float}
var _siting := false

## Put a field on the map. Its elevation is read from the land as it is *before*
## the field is there, so it sits at the natural height of its site instead of
## dragging the country up or down to meet it.
func register_field(at: Vector2, yaw: float, elev := INF) -> Dictionary:
	# In the flat frame, like the decks and for the same reason: this number is
	# handed to the extension, which levels the field on the plane and knows
	# nothing about the planet. `height_at` drops the result afterwards, so a
	# curved elevation stored here would have the drop taken off it twice --
	# and it was, leaving the opposing airfield's pavement in a 471 m crater.
	var e := elev
	if e == INF:
		_siting = true
		e = height_at(at.x, at.y) + planet_drop(at.x, at.y)
		_siting = false
	var f := {"at": at, "yaw": yaw, "elev": e}
	fields.append(f)
	# Straight over to the extension: the aerodrome is part of the height field
	# now, and everything that asks for a block of ground -- a terrain chunk, a
	# road profile, the map -- gets it applied there rather than looping over
	# the list again on this side.
	roads.push_world()
	return f

## Put the home field back on the land it is actually standing on.
##
## `RUNWAY_ELEV` is zero, which was right for as long as the world was flat and
## the home strip sat at sea level by definition. On the planet the chart is put
## on a country, and that country's ground is wherever the generator left it --
## 516 m up for the one this started on. Levelling the field to zero there does
## not lower the runway, it tells the extension to cut the whole aerodrome down
## through half a kilometre of hill, and the road network then runs down into
## the hole to meet it. Both the field test and the road test were reading the
## same 516 m.
##
## Called once the chart is on the chosen country, because until then there is
## no land under (0, 0) to ask about.
func resite_home_field() -> void:
	if not globe or fields.is_empty():
		return
	var f: Dictionary = fields[0]
	var at: Vector2 = f["at"]
	# As `register_field` samples: with the fields held off, so the strip takes
	# the natural height of its site rather than the height it has already been
	# levelled to.
	_siting = true
	f["elev"] = height_at(at.x, at.y) + planet_drop(at.x, at.y)
	_siting = false
	roads.push_world()

## A field's pavement as a world height. `elev` is stored flat because the
## extension levels the field there; this is that pavement once it has been
## dropped onto the sphere, which is what anything standing on it wants. Pass a
## point to get the height under that point: a runway follows the curve, so a
## strip three kilometres long is 37 m lower at the ends 78 km out -- tilted by
## the same eight tenths of a degree that gravity is.
func field_elev(fd: Dictionary, x := INF, z := INF) -> float:
	var at: Vector2 = fd["at"]
	var px: float = at.x if is_inf(x) else x
	var pz: float = at.y if is_inf(z) else z
	return float(fd["elev"]) - planet_drop(px, pz)

## The countries, and which one you are flying for.
##
## There is no centre to this planet and no main airfield on it. Each side has a
## country somewhere on the globe -- the same six the ground is divided between
## -- and starting a mission means starting in one of them. The chart is then
## centred on that country's aerodrome, which is what makes it *the* aerodrome
## for that sortie: the world is built around wherever you began.
##
## Where they are is `sphere::HOMELANDS` in the extension, which is also what
## raises the land under them; this side keeps only the names and their order.
## It was two tables once, and the copies disagreed about which way north was.
## The names, in the order the extension has them. Positions live there; this
## side only needs to know which country is which.
const HOMELAND_ORDER := ["usa", "uk", "france", "russia", "china", "iran"]
const HOMELANDS := {
	"usa": 0, "uk": 1, "france": 2, "russia": 3, "china": 4, "iran": 5,
}
## Whose side you are on. Chosen before the world is built, because the world is
## built around it.
var home_faction := "usa"

## A country's direction from the planet's centre.
##
## Asked of the extension rather than worked out here. This was a second copy of
## `sphere::HOMELANDS` with its own trigonometry, and the copy had north's sign
## the other way round: every country came out at the mirror of its own
## latitude, so the game asked about six places the generator had never raised
## land at and found three of them under the sea. The list below is names and
## the order they are in; where they *are* is the extension's business.
func homeland_dir(who: String) -> Vector3:
	if native == null:
		return Vector3.UP
	return native.homeland_dir(HOMELAND_ORDER.find(who) if HOMELAND_ORDER.has(who)
		else 0)

## Where this sortie begins. The chart is put here before anything is built.
func home_dir() -> Vector3:
	return homeland_dir(home_faction) if globe else Vector3.UP

## The landmass the world is built on.
##
## A settlement is not merely somewhere dry. On a flat world with one continent
## in it that distinction never came up; on a planet it is the difference
## between a trunk network and a trunk network that crosses an ocean, because
## the router will dutifully connect any two towns it is given and the survey
## does something desperate when it has to. Measured, towns on separate
## landmasses gave a design surface 280 m off the ground and gradients over
## 300 %.
##
## A flood fill over a coarse grid, out from the airfield, across land. One
## batched call to the extension for the heights and then a breadth-first walk:
## a few hundred thousand cells is nothing once the heights are not fetched one
## at a time.
const LAND_N := 512
const LAND_HALF := 768_000.0
var _land_mask := PackedByteArray()

func build_landmass() -> void:
	# The grid, the waterline and the fill, in one call.
	#
	# It was a quarter of a million cells thresholded here and then a flood fill
	# over the same quarter million that built a fresh array of the four
	# neighbour offsets for every cell it visited. Measured, 334 ms of a four
	# second cold start, and not one decision in any of it.
	_land_mask = native.landmass(LAND_HALF, LAND_N)
	if _land_mask.is_empty():
		push_warning("the airfield is not on land: no landmass to build on")

## Is this point on the same land as the airfield? True everywhere if the fill
## has not been run, so nothing is refused a site for want of an answer.
func on_home_land(x: float, z: float) -> bool:
	if _land_mask.is_empty():
		return true
	if absf(x) >= LAND_HALF or absf(z) >= LAND_HALF:
		return false
	var cell: float = LAND_HALF * 2.0 / float(LAND_N)
	var i := int((x + LAND_HALF) / cell)
	var j := int((z + LAND_HALF) / cell)
	return _land_mask[clampi(j, 0, LAND_N - 1) * LAND_N
		+ clampi(i, 0, LAND_N - 1)] == 1

## How much of the world is the landmass the airfield stands on, as a fraction
## of everything above water. Reported rather than gated: a world whose one
## continent is a tenth of its land is a world where most towns have nowhere to
## be, and that is worth seeing.
func landmass_share() -> float:
	if _land_mask.is_empty():
		return 1.0
	var on := 0
	for v in _land_mask:
		if v == 1:
			on += 1
	return float(on) / float(LAND_N * LAND_N)

## How much of a given field applies at a point, in that field's own frame.
func field_factor(fd: Dictionary, x: float, z: float) -> float:
	var d: Vector2 = Vector2(x, z) - (fd["at"] as Vector2)
	var c := cos(-float(fd["yaw"]))
	var sn := sin(-float(fd["yaw"]))
	var lx: float = d.x * c - d.y * sn
	var lz: float = d.x * sn + d.y * c
	# The levelled area has to be big enough for the mesh to draw it. Out where
	# the rings are coarse a cell is kilometres across, so a strip two by four
	# was smaller than one triangle and the flattening was invisible: the
	# pavement sat thirteen metres under the ground it was supposed to be on.
	var cell: float = Terrain.cell_at(x, z)
	var pad: float = maxf(cell * 2.5, 0.0)
	var dx := maxf(absf(lx) - (950.0 + pad), 0.0)
	var dz := maxf(absf(lz) - (1950.0 + pad), 0.0)
	return 1.0 - smoothstep(0.0, maxf(2600.0, cell * 4.0), sqrt(dx * dx + dz * dz))

func flat_factor(x: float, z: float) -> float:
	var best := 0.0
	for fd in fields:
		best = maxf(best, field_factor(fd, x, z))
	return best

## Where a point sits in a field's own frame, so runway and taxiway tests can be
## written once and asked of any of them.
func field_local(fd: Dictionary, x: float, z: float) -> Vector2:
	var d: Vector2 = Vector2(x, z) - (fd["at"] as Vector2)
	var c := cos(-float(fd["yaw"]))
	var sn := sin(-float(fd["yaw"]))
	return Vector2(d.x * c - d.y * sn, d.x * sn + d.y * c)

## What a height query wants applied, matching the extension's own flags: the
## made roads, the aerodromes, or both. The town platforms are always in --
## they are part of the land as soon as a town is sited.
const G_ROADS := 1
const G_FIELDS := 2
const G_ALL := 3
## The ground as the terrain mesh draws it, which differs from the ground as
## things stand on it in one place: a walled ramp in a town, which is drawn as a
## structure standing on the town's own ground. See `G_DRAWN` in world.rs.
const G_DRAWN := 4

## What the finished ground includes at this point in the pipeline. The
## corridor is invisible while the network is being surveyed, and the
## aerodromes while one of them is being sited.
func _ground_flags() -> int:
	var f := 0
	if not roads.in_survey:
		f |= G_ROADS
	if not _siting:
		f |= G_FIELDS
	return f

## Terrain elevation in metres. Single source of truth: the visual mesh, the
## landing gear and the crash test all sample this.
## The land at a point: the field, then everything built on it.
func height_at(x: float, z: float) -> float:
	# The field, the town platforms, the made roads and the aerodromes all come
	# back from the extension. The carrier decks are the one thing left on this
	# side: there are two of them and they move every frame.
	# ...and then dropped onto the sphere. The extension builds the field on a
	# plane and knows nothing about the planet; this is the single point where
	# a flat height becomes a height on a curved world.
	if globe:
		# The planetary field already carries the curve, so there is no drop to
		# take off here: it is a height on a round world, not a flat one bent.
		#
		# With the flags, like the flat world. Asked without them, a surveyor
		# siting an aerodrome read the ground with that aerodrome already
		# levelled into it and got back the elevation it was trying to choose.
		var fl: int = _ground_flags()
		if fl == G_ALL:
			return _deck_top(native.ground_globe(x, z), x, z)
		return _deck_top(native.ground_globe_flags(x, z, fl), x, z)
	return _deck_top(native.ground(x, z, _ground_flags()), x, z) - planet_drop(x, z)

## The ground as the terrain mesh draws it, which is now `height_at` everywhere:
## walled ramps in towns are drawn as terrain like any other bank. What
## something drawn down to the ground -- an abutment, a wall -- has to reach.
func drawn_height_at(x: float, z: float) -> float:
	if globe:
		return native.ground_globe_flags(x, z, G_ALL | G_DRAWN)
	return native.ground(x, z, G_ALL | G_DRAWN) - planet_drop(x, z)

## Ground height in the flat frame -- the height a surveyor works in, taken from
## the local horizontal rather than from world level. On a sphere the two part
## company by the drop, and the difference is not a slope anybody has to climb:
## a dead level road 138 km out reads as a 2.2 % gradient in world coordinates
## and the whole network reads as 1.5 % off camber. Gradients, cross falls and
## earthworks are set out against local up, so they are measured here.
func survey_height_at(x: float, z: float) -> float:
	return height_at(x, z) + planet_drop(x, z)

## A landable platform standing over the ground. Applied here rather than in
## the extension because it is the one part of the world that is not fixed once
## it is built -- a carrier under way carries its deck with it.
func _deck_top(h: float, x: float, z: float) -> float:
	if decks.is_empty():
		return h
	# A deck is registered in the flat frame, because on the flat world the drop
	# is taken off everything afterwards. On the planet nothing is taken off --
	# the field already carries the curve -- so the deck has to be dropped here
	# instead, or a carrier forty kilometres out lands aeroplanes forty-five
	# metres above its own flight deck.
	if globe:
		return maxf(h, deck_height(x, z) - planet_drop(x, z))
	return maxf(h, deck_height(x, z))

## How much of a settlement's levelled platform applies at a point. Zero is
## open country, one is inside the town proper.
func pad_weight(x: float, z: float) -> float:
	var w := 0.0
	for pad in roads.town_pads:
		var pc: Vector2 = pad["c"]
		var pr: float = pad["r"]
		var d := Vector2(x - pc.x, z - pc.y).length()
		if d < pr * 1.60:
			w = maxf(w, 1.0 - smoothstep(pr * 1.06, pr * 1.60, d))
	return w

func normal_at(x: float, z: float) -> Vector3:
	const E := 3.0
	var hl := height_at(x - E, z)
	var hr := height_at(x + E, z)
	var hd := height_at(x, z - E)
	var hu := height_at(x, z + E)
	return Vector3(hl - hr, 2.0 * E, hd - hu).normalized()

func on_runway(x: float, z: float) -> bool:
	for fd in fields:
		var l := field_local(fd, x, z)
		if absf(l.x) <= RUNWAY_HALF_W and absf(l.y) <= RUNWAY_LEN * 0.5:
			return true
	return false

## Paved surfaces (runway, taxiway loop, apron) roll better than grass.
func surface_grip(x: float, z: float) -> float:
	if deck_height(x, z) > -1e8:
		return 1.0
	if on_runway(x, z):
		return 1.0
	for fd in fields:
		var l := field_local(fd, x, z)
		if absf(l.x) >= 60.0 and absf(l.x) <= 92.0 and absf(l.y) <= RUNWAY_LEN * 0.5:
			return 1.0
		if absf(l.y) <= 1560.0 and absf(l.x) <= 95.0:
			return 1.0
	return 0.45

## Ground, slope and grip under a set of wheels at once: five numbers each --
## the height, the three of the normal, and the grip -- in the order they came
## in. `radii` says how big each wheel is, which is what decides whether it is
## touching: one in the air is given its height and nothing else.
##
## This is `height_at`, `normal_at` and `surface_grip` asked together, because
## asked apart they are six crossings of the extension boundary per wheel. A
## tank has fourteen road wheels and a sector holds forty-five vehicles, all of
## them integrating at 120 Hz: measured, forty-five thousand crossings a frame
## and 87 ms of a hundred millisecond frame, which the physics then spends
## twelve steps catching up on. One crossing a vehicle a step instead.
func wheel_ground(pts: PackedVector3Array,
		radii: PackedFloat64Array) -> PackedFloat64Array:
	return native.wheel_ground(pts, radii)


var decks: Array = []              # landable platforms: {origin, basis, half, y}

## Register a flight deck. `half` is the half extent in deck-local X/Z.
func register_deck(origin: Vector3, yaw: float, half: Vector2, deck_y: float) -> Dictionary:
	var d := {"origin": origin, "yaw": yaw, "half": half, "y": deck_y,
		"cos": cos(-yaw), "sin": sin(-yaw)}
	decks.append(d)
	return d

## Hand the decks to the extension, which is where the terrain mesh is built.
##
## A deck is the one part of the world that moves, so it cannot be published
## once with the roads and the aerodromes: it is pushed over just before the
## work that reads it goes out. Cheap -- there are never more than a handful --
## and the alternative is the mesher crossing back into script for every one of
## the nine hundred heights a chunk asks for.
func push_decks() -> void:
	var flat := PackedFloat32Array()
	flat.resize(decks.size() * 7)
	var at := 0
	for d in decks:
		var o: Vector3 = d["origin"]
		var hf: Vector2 = d["half"]
		flat[at] = o.x
		flat[at + 1] = o.z
		flat[at + 2] = d["cos"]
		flat[at + 3] = d["sin"]
		flat[at + 4] = hf.x
		flat[at + 5] = hf.y
		flat[at + 6] = d["y"]
		at += 7
	native.set_decks(flat)

## Deck-local coordinates of a world point, or INF when it is not over the deck.
func deck_local(d: Dictionary, x: float, z: float) -> Vector2:
	var dx: float = x - d["origin"].x
	var dz: float = z - d["origin"].z
	var lx: float = dx * d["cos"] - dz * d["sin"]
	var lz: float = dx * d["sin"] + dz * d["cos"]
	return Vector2(lx, lz)

func deck_height(x: float, z: float) -> float:
	for d in decks:
		var l := deck_local(d, x, z)
		if absf(l.x) <= d["half"].x and absf(l.y) <= d["half"].y:
			return d["y"]
	return -1e9


func buildable(x: float, z: float, flat := 0.86, clearance := 4.0,
		road_clear := 4.0) -> bool:
	var y := height_at(x, z)
	if y < WATER_LEVEL + clearance:
		return false
	if normal_at(x, z).y < flat:
		return false
	if not clear_of_roads(x, z, road_clear):
		return false
	if not clear_of_works(x, z, road_clear):
		return false
	if absf(x) < 340.0 and absf(z) < 2100.0:
		return false
	return true

## A wider keep-out for anything tall: pylons, masts and turbines must not stand
## in the approach path or on the airfield itself.
## True when nothing of the given half-width would be standing in a road here.
func clear_of_roads(x: float, z: float, half: float) -> bool:
	if roads.segments_indexed == 0:
		return true
	if roads.road_distance(x, z) < 13.0 + half:            # carriageway plus kerbs
		return false
	return true

## Clear of what the road network built that its centrelines do not show: a
## bridge and the legs onto it, which are not in the road index at all, and the
## bank or cutting the earthworks made, which reaches well past the kerb. A
## town laid out by the kerb alone put houses against the abutments, under the
## decks and half buried in the bank of a raised approach.
const WORKS_GAP := 8.0
func clear_of_works(x: float, z: float, half: float) -> bool:
	var q := Vector2(x, z)
	var need: float = roads.BRIDGE_HALF + WORKS_GAP + half
	for coll in [roads.road_bridges, roads.road_tunnels]:
		for br in coll:
			var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
			if pts.size() < 2:
				continue
			# a station or two out past each end, where the approach is
			var a0: Vector2 = pts[0]
			var a1: Vector2 = pts[pts.size() - 1]
			var e0: Vector2 = a0 + (a0 - pts[1]).normalized() * 60.0
			var e1: Vector2 = a1 + (a1 - pts[pts.size() - 2]).normalized() * 60.0
			if roads.seg_dist(q, e0, a0) < need or roads.seg_dist(q, a1, e1) < need:
				return false
			for i in pts.size() - 1:
				if roads.seg_dist(q, pts[i], pts[i + 1]) < need:
					return false
	if roads.corr.is_empty():
		return true
	# where the road has moved the ground, anywhere under the footprint
	var r: float = half + 4.0
	for o in [Vector2.ZERO, Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		var px: float = x + o.x
		var pz: float = z + o.y
		if absf(native.ground(px, pz, G_ALL) - native.ground(px, pz, G_ALL & ~G_ROADS)) > 0.6:
			return false
	return true

## Places a town must not be built over besides the aerodromes: [centre,
## radius]. The depot, for one: a town sited on its pad grew streets through
## the hangars.
var keep_out: Array = []

## Can a whole town of radius `r` stand at `c`? `clear_of_airfield` was asked
## of the centre alone, so a town a kilometre and a half across sited just
## outside the box ran its streets and its blocks across the runway, the apron
## and the approach lights. This is the disc against every aerodrome -- the
## pavement it is levelled over and the approach off each end, in that field's
## own frame -- and against everything in `keep_out`.
func town_clear(c: Vector2, r: float) -> bool:
	var need: float = r * 1.15 + 300.0
	for fd in fields:
		var l: Vector2 = field_local(fd, c.x, c.y)
		if rect_gap(l, Vector2(950.0, 2600.0)) < need:
			return false
		if rect_gap(l, Vector2(260.0, 5200.0)) < need * 0.6:
			return false
	for k in keep_out:
		if c.distance_to(k[0] as Vector2) < r * 1.15 + float(k[1]) + 100.0:
			return false
	return true

## How far a point in a rectangle's own frame is outside it (0 inside).
func rect_gap(l: Vector2, half: Vector2) -> float:
	var dx := maxf(absf(l.x) - half.x, 0.0)
	var dz := maxf(absf(l.y) - half.y, 0.0)
	return sqrt(dx * dx + dz * dz)

func clear_of_airfield(x: float, z: float) -> bool:
	if absf(x) < 620.0 and absf(z) < 2600.0:
		return false
	# and clear of the extended centreline where the approach lights run
	if absf(x) < 260.0 and absf(z) < 5200.0:
		return false
	return true


## Somebody killed somebody. `killer` may be "" for a blast nobody owns.
func kill(killer: String, killer_team: int, victim: String, victim_team: int,
		weapon: String, head := false) -> void:
	kill_event.emit({"k": killer, "kt": killer_team, "v": victim, "vt": victim_team,
		"w": weapon, "h": head})
	if OS.has_feature("headless") or OS.is_debug_build():
		print("[kill %6.1f] %s [%s%s] %s" % [Time.get_ticks_msec() * 0.001, killer, weapon,
			" HS" if head else "", victim])

## Swallow reports for a moment: a strike replayed from another machine says
## its own one line instead of the caller's "inbound, get down".
var mute_reports := false

func report(text: String, kind: int = Ev.INFO) -> void:
	if mute_reports:
		return
	mission_event.emit(text, kind)
	if OS.has_feature("headless") or OS.is_debug_build():
		print("[mission %6.1f] %s" % [Time.get_ticks_msec() * 0.001, text])

## Terrain masking. True when nothing between the two points is inside the
## height field — the test a radar, a seeker head and a pair of eyes all need,
## and previously duplicated inside the HUD where nothing else could reach it.
## The step is fine enough to catch a ridge line and coarse enough that a whole
## radar sweep's worth of calls costs nothing.
## `skip` ignores the first stretch of the ray. A radar is not blocked by the
## ground its own aeroplane is standing on: with the eye four metres up and the
## march starting immediately, every contact read as masked the moment you were
## at low level or on the runway, and the answer to pressing T was "no radar
## contacts" wherever you pointed it.
## Who is already being shot at, and by how many. Without this every hull in
## the fleet picked the same inbound round -- the nearest one -- and emptied
## cells at it together while everything else came through untouched.
var _engaged: Dictionary = {}

func engage_count(threat: Node) -> int:
	if not is_instance_valid(threat):
		return 0
	var rec: Variant = _engaged.get(threat.get_instance_id())
	if rec == null:
		return 0
	# an assignment goes stale: the round it was fired at arrives or is killed
	if Time.get_ticks_msec() - int((rec as Array)[0]) > 9000:
		return 0
	return int((rec as Array)[1])

func claim_engagement(threat: Node) -> void:
	if not is_instance_valid(threat):
		return
	var key := threat.get_instance_id()
	var n := engage_count(threat)
	_engaged[key] = [Time.get_ticks_msec(), n + 1]

## Whose part of the world this is. Culture varies by region rather than by
## anything the mission declares, so the props and the paint in a town match
## the country it stands in — and the country changes as you fly across the map.
func region_faction(x: float, z: float) -> String:
	var n: float
	var m: float
	if globe:
		# On the planet, and of the planet: the same piece of ground answers the
		# same way whatever chart is looking at it.
		var d := chart_to_dir(x, z)
		n = noise_faction3.get_noise_3d(d.x, d.y, d.z)
		m = noise_faction3.get_noise_3d(d.z + 4.0, d.x - 2.0, d.y + 7.0)
	else:
		n = noise_faction.get_noise_2d(x + 90000.0, z - 40000.0)
		m = noise_faction.get_noise_2d(z - 15000.0, x + 62000.0)
	# Which way the pair of noise fields points, not what they add up to.
	#
	# Averaging two noise samples and cutting the result into six equal value
	# bands looks even and is not: the sum of two roughly independent fields is
	# triangular, piled up in the middle, so the middle bands get nearly all the
	# map and the end ones get none. Measured over 20000 samples of the old
	# expression: Russia 45.7%, France 31.5%, China 12.5%, Britain 9.8%, the
	# United States 0.6% and Iran **zero**. Two of the six nationalities did not
	# exist anywhere in the world — no Iranian town, no Iranian ground, nowhere
	# for Iranian kit to be.
	#
	# The angle of the pair is very nearly uniform, because the joint
	# distribution is roughly radially symmetric, and it still moves smoothly
	# with position — so the regions stay large and organic instead of becoming
	# a checkerboard.
	var ang := atan2(m, n) / TAU + 0.5          # 0..1
	var pick := int(floor(ang * 6.0))
	match clampi(pick, 0, 5):
		0:
			return "usa"
		1:
			return "uk"
		2:
			return "france"
		3:
			return "russia"
		4:
			return "china"
		_:
			return "iran"

## Places worth flying to, and whose they are. Filled by the scenery.
var landmarks: Array = []

func register_landmark(nm: String, faction: String, at: Vector3, h: float) -> void:
	landmarks.append({"name": nm, "faction": faction, "at": at, "h": h})

## The stone a country builds in, near enough. Used for the landmarks so each
## one reads as belonging somewhere before you are close enough to see what it
## is.
func faction_colour(faction: String) -> Color:
	match faction:
		"france":
			return Color(0.42, 0.38, 0.34)
		"uk":
			return Color(0.58, 0.52, 0.40)
		"usa":
			return Color(0.52, 0.66, 0.60)
		"russia":
			return Color(0.66, 0.60, 0.52)
		"china":
			return Color(0.60, 0.46, 0.36)
		"iran":
			return Color(0.44, 0.56, 0.62)
		"free":
			# Independent towns: whitewash and pale timber, deliberately not
			# any of the national palettes.
			return Color(0.74, 0.71, 0.64)
		_:
			return Color(0.72, 0.68, 0.56)

func line_of_sight(from: Vector3, to: Vector3, skip := 0.0) -> bool:
	return native.sight_lines(PackedVector3Array([from]),
		PackedVector3Array([to]), skip)[0] != 0

## The same for a whole list of sight lines at once.
##
## The march is up to forty-eight height queries, and asked one line at a time
## each of those is its own crossing of the extension boundary. The head-up
## display's radar scope asks it of every contact on the scope every frame:
## fourteen aircraft in a fight is seven hundred crossings a frame, and measured
## that one panel was 1.0 ms of a 13 ms frame. Asked as a list it is one
## crossing and the marches run across every core.
func lines_of_sight(from: PackedVector3Array, to: PackedVector3Array,
		skip := 0.0) -> PackedByteArray:
	return native.sight_lines(from, to, skip)

## How far down a contact would have to go to break the line. Negative when it
## is already masked. Used by the AI to decide whether the terrain is worth
## hiding behind or whether it would just be flying into a valley for nothing.
func masking_depth(from: Vector3, to: Vector3) -> float:
	var span := from.distance_to(to)
	if span < 1.0:
		return 0.0
	var worst := 1e9
	var steps := clampi(int(span / 180.0), 6, 48)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var q: Vector3 = from.lerp(to, t)
		worst = minf(worst, q.y - height_at(q.x, q.z))
	return worst if worst < 1e8 else 0.0

## What to call a thing on screen. A node's `name` is not it: set before the
## node joins the tree, a name that collides with a sibling is replaced by Godot
## with a generated one, so the second Type 45 and the second patrol boat showed
## up on the radar as "@Node3D@194" and "@Node3D@197".
func label_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "—"
	if n.has_method("display_name"):
		return String(n.call("display_name"))
	var nm := String(n.name)
	return "contact" if nm.begins_with("@") else nm

## True while the TAB menu is up. It is worked from the keyboard -- W/S and the
## arrows to move through it, 1 to 9 to pick -- and every one of those is also
## the stick or the weapon select, which the vehicles poll straight from the
## input actions. Picking "all stop" off a ship's menu with S rang down astern
## on the way, and choosing the third item selected weapon three.
var menu_keys := false
const MENU_ACTIONS := [&"pitch_up", &"pitch_down", &"weapon_1", &"weapon_2",
	&"weapon_3", &"weapon_4", &"weapon_5", &"weapon_6", &"weapon_7", &"weapon_8"]

## True while the sensor page is up. CTRL there is the modifier for CTRL+T,
## the designate key -- and CTRL is also the throttle. Holding it to designate
## pulled the power back, and any throttle input is the disconnect for the
## altitude hold and the auto hover, so every designation knocked the
## aircraft out of the hold it had been put in precisely so the pilot could
## work the sensor. With the page up CTRL is the modifier only; Z and the
## shoulder button still bring the power back.
var sensor_keys := false

## How far a radar can see, lock and engage `tgt` from, given what it does
## at `base` against an ordinary target. Radar range goes as the fourth root of
## the radar cross-section: an F-22 (0.12) is found at under two thirds of the
## distance, a B-2 (0.04) at under half. Stealth was a number on the spec that
## only the AI's choice of whom to chase read: every battery, fighter and
## launcher locked and fired at a B-2 from as far off as at an airliner.
func radar_reach(base: float, tgt: Object) -> float:
	if tgt == null or not is_instance_valid(tgt) or not tgt.has_method("radar_cross_section"):
		return base
	var rcs: float = maxf(float(tgt.call("radar_cross_section")), 0.0001)
	return base * clampf(pow(rcs, 0.25), 0.3, 1.25)

func strength(action: StringName) -> float:
	if typing or menu_open or spectating or (menu_keys and MENU_ACTIONS.has(action)):
		return 0.0
	if action == &"throttle_down" and sensor_keys and Input.is_physical_key_pressed(KEY_CTRL):
		return 1.0 if Input.is_physical_key_pressed(KEY_Z) \
			or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) else 0.0
	return Input.get_action_strength(action)

func held(action: StringName) -> bool:
	if _blocked.has(action) or (menu_keys and MENU_ACTIONS.has(action)):
		return false
	return not typing and not menu_open and not spectating and Input.is_action_pressed(action)

## Discrete key presses, latched from the input event rather than polled.
##
## `Input.is_action_just_pressed` is true only during the frame the press was
## registered, and everything that reads it here does so from
## `_physics_process`. Physics runs at 120 Hz and the renderer does not, so a
## press could land between physics ticks and be gone before anyone looked —
## which is why T cycled targets *sometimes*. Latching the press when the event
## arrives and clearing it when somebody consumes it makes it exact: every press
## is seen once, and no press is seen twice.
var _taps := {}

## Buttons that were already down when something changed under them. A mouse
## press that launched the mission is still held on the first frame of it, and
## everything that reads the trigger by polling saw a shoot command the instant
## you arrived — so choosing a vehicle fired its weapon.
var _blocked: Dictionary = {}

func block_until_released(actions: Array) -> void:
	for a in actions:
		_blocked[a] = true
		_taps.erase(a)

## The sea's own clock, advanced with the physics rather than with the frame.
##
## A hull floats in `_physics_process` and reads the swell there. Advanced on
## render frames, the clock could be several frames ahead or behind of what the
## hull last saw -- headless especially, where the two rates are not tied -- and
## a test that asks where the surface is *now* disagrees with a hull that
## settled to where it was *then*. Measured, that drift reached 0.1 m against a
## swell that only moves 8 mm in a tick. One clock, stepped once, and the
## question has one answer.
func _physics_process(delta: float) -> void:
	sea_time += delta
	# whoever is flying on time warp adds the rest: see `LaunchVehicle`
	space_time += delta

func _process(_delta: float) -> void:
	if discord_presence != null:
		discord_presence.update_presence(
			"1575674183667556432",
			presence_mode if presence_mode != "" else String(mission),
			presence_seat if presence_seat != "" else String(selected_jet),
			# Nothing running yet -- the start-up, the hangar -- is the hangar.
			# It fell back to the hangar's defaults and said "Runway
			# Operations, flying an F-22" from the moment the game opened.
			menu_open or presence_mode == "",
		)
	if _blocked.is_empty():
		return
	for a in _blocked.keys():
		if not Input.is_action_pressed(a):
			_blocked.erase(a)
			# and the press it was blocking goes with it. The press is latched
			# as a tap when its event arrives, which can be after whatever
			# blocked it had already cleared the latch -- so a quick tap of U
			# got a man out of the aeroplane, and the same tap, still fresh
			# when the key came up, put him straight back in.
			_taps.erase(a)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if discord_presence != null:
			discord_presence.shutdown_native()

func _input(e: InputEvent) -> void:
	if typing or not (e is InputEventKey or e is InputEventMouseButton):
		return
	if e is InputEventKey and (e as InputEventKey).echo:
		return
	for a in InputMap.get_actions():
		if e.is_action_pressed(a) and not _blocked.has(a):
			_taps[a] = Time.get_ticks_msec()

func tapped(action: StringName) -> bool:
	if typing or menu_open or spectating or _blocked.has(action) \
			or (menu_keys and MENU_ACTIONS.has(action)):
		return false
	var at: int = _taps.get(action, 0)
	if at == 0:
		return false
	_taps.erase(action)
	# A press nobody looked at for a quarter of a second was meant for a screen
	# that is no longer up; do not let it fire late.
	return Time.get_ticks_msec() - at < 250

# --------------------------------------------------------------------------
## What key an action is actually on, for anything that prints a control on the
## screen. The HUD carried its key labels as literal text, so when the
## countermeasures moved -- flares off N onto C, chaff off B onto V, to get the
## chaff off the bomb bay key -- the help page was updated and the flight strip
## was not. It went on telling you to press N and B for the rest of the sortie.
## Read the binding instead and it cannot drift again.
# ------------------------------------------------------------- the frame budget
#
# Where the frame goes, measured rather than guessed.
#
# A profiler that is always on is a tax on every frame it measures, and one that
# is never on means optimising by argument. This is two `Time.get_ticks_usec()`
# calls around a block, skipped entirely unless something asked for them, and it
# reports in the same units the frame is spent in.
var profiling := false
var _prof: Dictionary = {}
var _prof_n: Dictionary = {}
var _prof_frames := 0

## Start timing a block. Returns the stamp to hand back to `prof_end`.
func prof_at() -> int:
	return Time.get_ticks_usec() if profiling else 0

## Close one. Named at this end so the name sits with the number it produced.
func prof_end(tag: StringName, t0: int) -> void:
	if not profiling or t0 == 0:
		return
	_prof[tag] = float(_prof.get(tag, 0.0)) + float(Time.get_ticks_usec() - t0)
	_prof_n[tag] = int(_prof_n.get(tag, 0)) + 1

func prof_frame() -> void:
	if profiling:
		_prof_frames += 1

func prof_reset() -> void:
	_prof.clear()
	_prof_n.clear()
	_prof_frames = 0

## What each block cost per frame, in microseconds, worst first.
func prof_report() -> Array:
	var out: Array = []
	var f: float = maxf(float(_prof_frames), 1.0)
	for k in _prof.keys():
		out.append([String(k), float(_prof[k]) / f, int(_prof_n[k])])
	out.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return out

func prof_frames() -> int:
	return _prof_frames

## A screen is up that wants the pointer, so nothing may capture the mouse.
##
## Freelook is on ALT and CMD, and the map plants an objective on CTRL or CMD
## and click. Holding CMD over the map therefore engaged freelook, which
## captures the mouse -- and a captured cursor is parked in the middle of the
## screen, so the marker could only ever be dropped dead centre.
var ui_pointer := false


